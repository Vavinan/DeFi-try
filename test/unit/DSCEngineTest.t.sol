// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/Script.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";
import {ERC20MockCustom} from "../../script/ERC20MockCustom.s.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig helperConfig;
    address ethUsdPriceFeed;
    address wEth;
    address btcUsdPriceFeed;
    address wBtc;

    address public USER = makeAddr("USER");
    address public LIQUIDATOR = makeAddr("LIQUIDATOR");
    uint256 public constant COLLATERAL_AMOUNT = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant DEBT_AMOUNT = 50 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, wEth, wBtc,) = helperConfig.activeNetworkConfig();

        ERC20MockCustom(wEth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20MockCustom(wEth).mint(LIQUIDATOR, STARTING_ERC20_BALANCE);
    }
    uint256 public constant AMOUNT_TO_MINT = 100 ether;

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(wEth, COLLATERAL_AMOUNT);
        engine.mintDSC(AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(wEth, COLLATERAL_AMOUNT);
        vm.stopPrank();
        _;
    }

    ////////////////////////////////////////////
    ///         CONSTRUCTOR TESTS            ///
    ////////////////////////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertIfTokenLengthDoesntMatchPriceFeedLength() public {
        tokenAddresses.push(wEth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesLenghtMustBeEqual.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ////////////////////////////////////////////
    ///            PRICE TESTS               ///
    ////////////////////////////////////////////

    function testGetUSDValue() public view {
        uint256 ethAmount = 15e18; //15e18 * 2000/ETH = 30,000e18
        uint256 expectedUSD = 30000e18;
        uint256 actualUSD = engine.getUSDValue(wEth, ethAmount);
        assert(actualUSD == expectedUSD);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        // $200 per eth so 100/2000 => 0.05
        uint256 expectedWEth = 0.05 ether;
        uint256 actualWEth = engine.getTokenAmountFromUsd(wEth, usdAmount);
        assert(actualWEth == expectedWEth);
    }

    ////////////////////////////////////////////
    ///      DEPOSIT COLLATERAL TESTS        ///
    ////////////////////////////////////////////

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(engine), COLLATERAL_AMOUNT);

        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeAboveZero.selector);
        engine.depositCollateral(wEth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20MockCustom ranToken = new ERC20MockCustom("RAN", "RAN", USER, COLLATERAL_AMOUNT);
        vm.startPrank(USER);

        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        engine.depositCollateral(address(ranToken), COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function testDepositCollateralAndGetAccountInformation() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUSD) = engine.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(wEth, collateralValueInUSD);
        assert(totalDscMinted == expectedTotalDscMinted);
        assert(COLLATERAL_AMOUNT == expectedDepositAmount);
    }

    ////////////////////////////////////////////
    ///              AI TESTS                ///
    ////////////////////////////////////////////

    function testOwnershipTransferredToEngine() public {
        assertEq(dsc.owner(), address(engine));
    }

    function testCollateralDepositUpdatesBalances() public depositedCollateral {
        uint256 userBalance = ERC20Mock(wEth).balanceOf(USER);
        assertEq(userBalance, STARTING_ERC20_BALANCE - COLLATERAL_AMOUNT);

        uint256 collateralValue = engine.getUSDValue(wEth, COLLATERAL_AMOUNT);
        (uint256 totalDscMinted, uint256 collateralValueInUSD) = engine.getAccountInformation(USER);

        assertEq(totalDscMinted, 0);
        assertEq(collateralValueInUSD, collateralValue);
    }

    function testMintDSCWithCollateral() public depositedCollateral {
        vm.startPrank(USER);
        engine.mintDSC(5 ether); // mint 5 DSC
        vm.stopPrank();

        assertEq(dsc.balanceOf(USER), 5 ether);
    }

    function testDepositCollateralAndMintDSC() public {
        vm.startPrank(USER);

        ERC20Mock(wEth).approve(address(engine), COLLATERAL_AMOUNT);

        engine.depositCollateralAndMintDSC(wEth, COLLATERAL_AMOUNT, AMOUNT_TO_MINT);

        vm.stopPrank();

        assertEq(dsc.balanceOf(USER), AMOUNT_TO_MINT);

        (uint256 minted,) = engine.getAccountInformation(USER);

        assertEq(minted, AMOUNT_TO_MINT);
    }

    function testMintRevertsIfHealthFactorBroken() public depositedCollateral {
        uint256 amountToMint = 10001 ether;

        vm.startPrank(USER);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 999900009999000099));

        engine.mintDSC(amountToMint);

        vm.stopPrank();
    }

    function testBurnDSC() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);

        dsc.approve(address(engine), AMOUNT_TO_MINT);

        engine.burnDSC(AMOUNT_TO_MINT);

        vm.stopPrank();

        assertEq(dsc.balanceOf(USER), 0);

        (uint256 minted,) = engine.getAccountInformation(USER);

        assertEq(minted, 0);
    }

    function testRedeemCollateral() public depositedCollateral {
        vm.startPrank(USER);

        engine.redeemCollateral(wEth, COLLATERAL_AMOUNT);

        vm.stopPrank();

        uint256 userBalance = ERC20Mock(wEth).balanceOf(USER);

        assertEq(userBalance, STARTING_ERC20_BALANCE);
    }

    function testRedeemCollateralRevertsIfHealthFactorBroken() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);

        vm.expectRevert();

        engine.redeemCollateral(wEth, 300 ether);

        vm.stopPrank();
    }

    function testCannotLiquidateHealthyUser() public depositedCollateralAndMintedDsc {
        vm.startPrank(LIQUIDATOR);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);

        engine.liquidate(wEth, USER, 10 ether);

        vm.stopPrank();
    }

    function testMintZeroReverts() public {
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeAboveZero.selector);

        engine.mintDSC(0);
    }

    function testBurnZeroReverts() public {
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeAboveZero.selector);

        engine.burnDSC(0);
    }

    function testRedeemZeroReverts() public {
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeAboveZero.selector);
        engine.redeemCollateral(wEth, 0);
    }

    function testGetCollateralTokensReturnsCorrectList() public {
        address[] memory tokens = engine.getCollateralTokens();
        assertEq(tokens.length, 2); // wEth and wBtc
        assertEq(tokens[0], wEth);
        assertEq(tokens[1], wBtc);
    }

    function testGetCollateralTokenPriceFeed() public {
        address feed = engine.getCollateralTokenPriceFeed(wEth);
        assertEq(feed, ethUsdPriceFeed);
    }

    function testGetHealthFactorForUserWithNoMintedDSC() public depositedCollateral {
        uint256 healthFactor = engine.getHealthFactor(USER);
        assertEq(healthFactor, type(uint256).max);
    }

    function testCollateralBalanceOfUser() public depositedCollateral {
        uint256 balance = engine.getCollateralBalanceOfUser(USER, wEth);
        assertEq(balance, COLLATERAL_AMOUNT);
    }

    function testRedeemCollateralForDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(engine), AMOUNT_TO_MINT);
        engine.redeemCollateralForDSC(wEth, COLLATERAL_AMOUNT, AMOUNT_TO_MINT);
        vm.stopPrank();
        assert(dsc.balanceOf(USER) == 0);
        assert(engine.getCollateralBalanceOfUser(USER, wEth) == 0);
        uint256 userBalance = ERC20Mock(wEth).balanceOf(USER);
        assertEq(userBalance, STARTING_ERC20_BALANCE);
    }

    function testHealthFactorCalculation() public {
        uint256 totalMinted = 100 ether;
        uint256 collateralUsd = 1000 ether;

        uint256 healthFactor = engine.calculateHealthFactor(totalMinted, collateralUsd);

        // (1000 * 50 /100) * 1e18 /100
        uint256 expected = 5e18;

        assertEq(healthFactor, expected);
    }

    function testHealthFactorAfterMint() public depositedCollateralAndMintedDsc {
        uint256 hf = engine.getHealthFactor(USER);

        assertEq(hf, 100e18);
    }

    function testRedeemCollateralAfterBurningAllDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);

        dsc.approve(address(engine), AMOUNT_TO_MINT);

        engine.burnDSC(AMOUNT_TO_MINT);

        engine.redeemCollateral(wEth, COLLATERAL_AMOUNT);

        vm.stopPrank();

        assert(ERC20Mock(wEth).balanceOf(USER) == STARTING_ERC20_BALANCE);
    }

    function testLiquidatorReceivesBonusCollateral() public depositedCollateralAndMintedDsc {
        ERC20MockCustom(wEth).mint(LIQUIDATOR, COLLATERAL_AMOUNT);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(wEth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(wEth, COLLATERAL_AMOUNT);
        engine.mintDSC(DEBT_AMOUNT);
        dsc.approve(address(engine), DEBT_AMOUNT);
        vm.stopPrank();

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(18e8);

        uint256 balanceBefore = ERC20Mock(wEth).balanceOf(LIQUIDATOR);

        vm.prank(LIQUIDATOR);
        engine.liquidate(wEth, USER, DEBT_AMOUNT);

        uint256 balanceAfter = ERC20Mock(wEth).balanceOf(LIQUIDATOR);
        vm.stopPrank();
        assert(balanceAfter > balanceBefore);
    }
}
