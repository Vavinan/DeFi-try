// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "../src/libraries/OracleLib.sol";

/**
 * @title DSCEngine
 * @author Vavinan
 *
 * This is system is designed to be minimal as possible and have the tokens maintain a 1 token == $1 peg
 *  Exogeneous collateral
 *  Dollar pegged
 *  Algorithmically stable
 *
 * It is similar do DAI if it has no governance, no fees and was only backed by wEth and wBTC
 *
 * This DSC system should always be "overcollateralized". At no point, should the value of all collateral <= the $ backed value of all the DSCs
 *
 * @notice This contract is the core of the DSC System. It handles the logic of minting and redeeming DSC as well as depositing and & withdrawing the collateral
 *
 * @notice This contract is very loosely based on the MkerDAO DSS (DAI) system
 */

contract DSCEngine is ReentrancyGuard {
    ////////////////////////////////////////////
    ///               ERRORS                 ///
    ////////////////////////////////////////////
    error DSCEngine__AmountMustBeAboveZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesLenghtMustBeEqual();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__InvalidPrice();

    ////////////////////////////////////////////
    ///                TYPES                 ///
    ////////////////////////////////////////////

    using OracleLib for AggregatorV3Interface;

    ////////////////////////////////////////////
    ///          STATE VARIABLES             ///
    ////////////////////////////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATOR_BONUS = 10; //10% bonus

    // 200% <-> 110% safe range

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    ////////////////////////////////////////////
    ///              EVENTS                  ///
    ////////////////////////////////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    ////////////////////////////////////////////
    ///             MODIFIERS                ///
    ////////////////////////////////////////////

    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert DSCEngine__AmountMustBeAboveZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    ////////////////////////////////////////////
    ///             FUNCTIONS                ///
    ////////////////////////////////////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesLenghtMustBeEqual();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }
    ////////////////////////////////////////////
    ///        EXTERNAL FUNCTIONS            ///
    ////////////////////////////////////////////

    /**
     *
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param collateralAmount The amount of collateral to deposit
     * @param amountDscToMint The amount of decentralized stable coin to mint
     *
     * @notice This function will deposit your collateral and mint DSC in one transaction
     */

    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 collateralAmount,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, collateralAmount);
        mintDSC(amountDscToMint);
    }

    /**
     * @notice follows CEI
     *
     * @param tokenCollateralAddress  The address of the token to deposit as collateral
     * @param collateralAmount The amount of collateral to deposit
     */

    function depositCollateral(address tokenCollateralAddress, uint256 collateralAmount)
        public
        moreThanZero(collateralAmount)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += collateralAmount;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, collateralAmount);
        bool successStatus = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), collateralAmount);
        if (!successStatus) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @notice follows CEI
     * @param tokenCollateralAddress The address of the token to redeem as collateral
     * @param collateralAmount The amount of collateral to redeem
     * @param amountDscToBurn The amount of decentralized stable coin to burn
     *
     * This function will burn DSC and redeem collateral in one transaction
     */

    function redeemCollateralForDSC(address tokenCollateralAddress, uint256 collateralAmount, uint256 amountDscToBurn)
        external
    {
        burnDSC(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, collateralAmount);
        // redeemCollateral already checks health factor
    }

    /* In order to redeem collateral:
        1. health factor must be over 1 After collateral pulled out

    */
    function redeemCollateral(address tokenCollateralAddress, uint256 collateralAmount)
        public
        moreThanZero(collateralAmount)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, collateralAmount);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows CEI
     * @param amountDscToMint The amount of decentralized stable coin to mint
     * @notice Must have more collateral value than minimum threshold
     */
    function mintDSC(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDSC(uint256 amountDscToBurn) public moreThanZero(amountDscToBurn) {
        _burnDSC(amountDscToBurn, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // maybe it wont hit this
    }

    /**
     *
     * @param collateral The ERC20 Collateral address to liquidate from the user
     * @param user The user whose health factor is broken. _healthFactor < MIN_HEALTH_FACTOR
     * @param deptToCover The amount of DSC to burn to imporve the user's health factor
     *
     * @notice You can partially liquidte a user
     * @notice You will get a liquidation bonus for taking the users funds
     * @notice This function assumes the protocal will be roughly 200% overCollateralized in order for this to work
     *
     * @notice A known bug is  if the protocol were 100% or less collateralized, then we wouldn't be able to incentivize the liquidators
     *
     * For example, if the price of the collateral plumented before anyone could be liquidated
     *
     * FOLLOW CEI
     */

    // If someone is almost undercollateralized the system will pay you to liquidate them
    function liquidate(address collateral, address user, uint256 deptToCover)
        external
        moreThanZero(deptToCover)
        nonReentrant
    {
        // check health factor
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        // burn DSC
        // Take their collateral
        // Example of bad user: $140 ETH, $100 DSC
        // dept to cover = $100
        // $100 of DSC = ??? ETH?
        uint256 tokenAmountFromDeptCovered = getTokenAmountFromUsd(collateral, deptToCover);
        // give them 10% bonus
        // should implement a feature to liquidate in the event of the protocol is insolvent add sweap the extra amounts into a treasury
        // 0.05 ETH * 10/100 = 0.005 ETH. The liquidator gets 0.055 eth
        uint256 bonusCollateral = tokenAmountFromDeptCovered * LIQUIDATOR_BONUS / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDeptCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);
        _burnDSC(deptToCover, user, msg.sender);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUSD)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUSD);
    }

    ////////////////////////////////////////////
    ///   PRIVATE & INTERNAL VIEW FUNCTIONS  ///
    ////////////////////////////////////////////

    /**
     *
     * @dev Low-level internal function, do not call unless function calling it is checking for health factor being broken
     */

    function _burnDSC(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        // this is hypothetically unreachable
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 collateralAmount)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= collateralAmount;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, collateralAmount);
        bool successStatus = IERC20(tokenCollateralAddress).transfer(to, collateralAmount);
        if (!successStatus) {
            revert DSCEngine__TransferFailed();
        }
        // _revertIfHealthFactorIsBroken(msg.sender);
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUSD)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUSD = getAccountCollateralValue(user);
    }

    /**
     *
     * @return how close to liquidation a user is
     *
     * If a user goes below 1, then they can get liquidated
     */

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);
        // if (totalDscMinted == 0) {
        //     return type(uint256).max;
        // }
        // uint256 collateralAdjustedForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        // return collateralAdjustedForThreshold * PRECISION / totalDscMinted;

        return _calculateHealthFactor(totalDscMinted, collateralValueInUSD);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUSD)
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) {
            return type(uint256).max;
        }
        uint256 collateralAmountAdjustedForThreshold =
            (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return collateralAmountAdjustedForThreshold * 1e18 / totalDscMinted;
    }

    ////////////////////////////////////////////
    ///   PUBLIC & EXTERNAL VIEW FUNCTIONS   ///
    ////////////////////////////////////////////

    function getTokenAmountFromUsd(address token, uint256 usdAmountinWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        //(, int256 price,,,) = priceFeed.latestRoundData();
        (, int256 price,,,) = priceFeed.stalePriceFeedCheckLatestRoundData();
        //
        // ($10e18 * 1e18) / ($2000e8 * 1e18)
        //
        if (price <= 0) {
            revert DSCEngine__InvalidPrice();
        }
        return (usdAmountinWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUSD) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUSD += getUSDValue(token, amount);
        }
        return totalCollateralValueInUSD;
    }

    function getUSDValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        //(, int256 price,,,) = priceFeed.latestRoundData();
        (, int256 price,,,) = priceFeed.stalePriceFeedCheckLatestRoundData();
        if (price <= 0) {
            revert DSCEngine__InvalidPrice();
        }
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountInformation(address user)
        public
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUSD)
    {
        (totalDscMinted, collateralValueInUSD) = _getAccountInformation(user);
    }

    function getCollateralTokenPriceFeed(address token) public view returns (address priceFeed) {
        return s_priceFeeds[token];
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getMineHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getCollateralBalanceOfUser(address user, address token) public view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }
}

