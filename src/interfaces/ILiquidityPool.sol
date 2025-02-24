// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IERC4626.sol";

interface ILiquidityPool is IERC4626 {
    enum PoolStatus {
        Active, // Accepting deposits
        Locked, // Deposit window closed
        Settled, // Funds sent to issuer
        Matured, // Returns received
        Defaulted, // Issuer defaulted
        EmergencyShutdown // Emergency state
    }

    struct PoolInfo {
        string name;
        string symbol;
        address asset;
        uint256 epochStart;
        uint256 epochEnd;
        uint256 maturityDate;
        uint256 minInvestment;
        uint256 yieldRate;
        bool isDiscounted;
        bytes32 instrumentHash;
    }

    function initialize(address manager, address escrow, PoolInfo calldata info) external;

    function status() external view returns (PoolStatus);
    function poolInfo() external view returns (PoolInfo memory);
    function expectedReturn() external view returns (uint256);
}
