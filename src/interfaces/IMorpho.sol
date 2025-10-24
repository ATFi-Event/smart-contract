// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

type Id is bytes32;

interface IMorpho {
    struct MarketParams {
        address loanToken;
        address collateralToken;
        address oracle;
        address irm;
        uint256 lltv;
    }

    struct Market {
        uint128 totalSupplyAssets;
        uint128 totalSupplyShares;
        uint128 totalBorrowAssets;
        uint128 totalBorrowShares;
        uint128 lastUpdate;
        uint128 fee;
    }

    struct Position {
        uint256 supplyShares;
        uint128 borrowShares;
        uint128 collateral;
    }

    function supply(MarketParams memory marketParams, uint256 assets, uint256 shares, address onBehalf, bytes calldata data) external;
    function withdraw(MarketParams calldata marketParams, uint256 assets, uint256 shares, address onBehalf, address receiver) external returns (uint256, uint256);
    function supplyCollateral(MarketParams calldata marketParams, uint256 assets, address onBehalf, bytes calldata data) external;
    function withdrawCollateral(MarketParams calldata marketParams, uint256 assets, address onBehalf, address receiver) external;

    function createMarket(MarketParams calldata marketParams) external;
    function idToMarketParams(Id id) external view returns (MarketParams memory);
    function market(Id id) external view returns (Market memory);
    function position(Id id, address user) external view returns (Position memory);

    function expectedSupplyAssets(MarketParams calldata marketParams, address user) external view returns (uint256);
    function expectedBorrowAssets(MarketParams calldata marketParams, address user) external view returns (uint256);

    function owner() external view returns (address);
    function feeRecipient() external view returns (address);
}

interface IMorphoOracle {
    function price(address token) external view returns (uint256);
}