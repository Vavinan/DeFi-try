// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;
import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ERC20MockCustom} from "../script/ERC20MockCustom.s.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wEthUsdPriceFeed;
        address wBtcUsdPricefeed;
        address wEth;
        address wBtc;
        uint256 deployerkey;
    }

    uint256 public DEFAULT_ANVIL_KEY = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wEthUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wBtcUsdPricefeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            wEth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wBtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerkey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wEthUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();

        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        //ERC20Mock wEthMock = new ERC20Mock("WETH", "WETH", msg.sender, 1000e8);
        ERC20MockCustom wEthMock = new ERC20MockCustom("WETH", "WETH", msg.sender, 1000e8);

        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        //ERC20Mock wBtcMock = new ERC20Mock("WBTC", "WBTC", msg.sender, 1000e8);
        ERC20MockCustom wBtcMock = new ERC20MockCustom("WBTC", "WBTC", msg.sender, 1000e8);

        vm.stopBroadcast();
        return NetworkConfig({
            wEthUsdPriceFeed: address(ethUsdPriceFeed),
            wBtcUsdPricefeed: address(btcUsdPriceFeed),
            wEth: address(wEthMock),
            wBtc: address(wBtcMock),
            deployerkey: DEFAULT_ANVIL_KEY
        });
    }
}
