// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

// What are the invariants here
/**
 * 1. The total supply of DSC should be less than the total value of collateral
 * 2. Getter view functions should never revert <- evergreen invariant
 *
 */

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console2} from "forge-std/console2.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine engine;
    HelperConfig helperConfig;
    DecentralizedStableCoin dsc;
    address wEth;
    address wBtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, helperConfig) = deployer.run();
        (,, wEth, wBtc,) = helperConfig.activeNetworkConfig();
        handler = new Handler(engine, dsc);
        //targetContract(address(engine));
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // get the value of all the collateral in the protocol
        // compare it to all the dept (dsc)
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalwEthDeposited = IERC20(wEth).balanceOf(address(engine));
        uint256 totalwBtcDeposited = IERC20(wBtc).balanceOf(address(engine));

        uint256 wEthValue = engine.getUSDValue(wEth, totalwEthDeposited);
        uint256 wBtcValue = engine.getUSDValue(wBtc, totalwBtcDeposited);
        console2.log("WETH: ", wEthValue);
        console2.log("WBTC: ", wBtcValue);
        console2.log("TOTAL SUPPLY: ", totalSupply);
        console2.log("MINTED: ", handler.timesMintIsCalled());
        assert(wEthValue + wBtcValue >= totalSupply);
    }

    function invariant_gettersShouldNotRevert() public view {
        engine.getLiquidationThreshold();
        engine.getMineHealthFactor();
        engine.getCollateralTokens();
        engine.getDsc();
    }
}

// The following is just a OPEN METHOD
/*
contract InvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine engine;
    HelperConfig helperConfig;
    DecentralizedStableCoin dsc;
    address wEth;
    address wBtc;




    function setUp() external{
        deployer = new DeployDSC();
        (dsc,engine, helperConfig) = deployer.run();
        (,,wEth,wBtc,) = helperConfig.activeNetworkConfig();

        targetContract(address(engine));
        console2.log("setup complete");
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public {
        // get the value of all the collateral in the protocol
        // compare it to all the dept (dsc)
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalwEthDeposited = IERC20(wEth).balanceOf(address(engine));
        uint256 totalwBtcDeposited = IERC20(wBtc).balanceOf(address(engine));

        uint256 wEthValue = engine.getUSDValue(wEth, totalwEthDeposited);
        uint256 wBtcValue = engine.getUSDValue(wBtc, totalwBtcDeposited);
        console2.log("WETH: ", wEthValue);
        console2.log("WBTC: ", wBtcValue);
        assert(wEthValue + wBtcValue >= totalSupply);
    }
} */