// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Vavinan
 * @notice This library is used to check the chainlink oracle if the price feed is stale.
 * If the price feed is stale function will revert and render the DSCEngine is unusable (by design)
 * The DSCEngine should freeze if the price becomes stale
 */

library OracleLib {
    error OracleLib__PriceFeedIsStale();

    uint256 private constant TIMEOUT = 3 hours; // 3*60*60 seconds

    function stalePriceFeedCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();
        uint256 secondsSinceLastUpdate = block.timestamp - updatedAt;
        if (secondsSinceLastUpdate > TIMEOUT) {
            revert OracleLib__PriceFeedIsStale();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
