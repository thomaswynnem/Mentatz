// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract PriceOracle {
    AggregatorV3Interface internal priceFeedEth;

    constructor() {
        // Initialize the price feed contract for ETH/USD
        priceFeedEth = AggregatorV3Interface(0x5f4eC3Df9cbd43714fe2740f5E3616155c5B8419); // Mainnet address
    }

    function getLatestPrice() public view returns (int256) {
        (,int256 price,,,) = priceFeedEth.latestRoundData();
        return price;
    }

    function DollarLimit(uint256 maxinput) public view returns (uint256) {
        int256 price = getLatestPrice(); 
        uint256 usdAmount = maxinput * 1e18;   // $20 in 18 decimal wei

        uint256 ethPrice = uint256(price);

        // Adjust for decimals: (usd * 1e8) / price = ETH in wei
        return (usdAmount * 1e8) / ethPrice;
    }
}