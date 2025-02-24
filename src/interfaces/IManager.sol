// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IManager {
    enum InstrumentType {
        TBill,
        CommercialPaper,
        DebtNote
    }

    struct InstrumentInfo {
        InstrumentType iType;
        uint256 maturityDate;
        uint256 yieldRate; // in basis points (e.g., 800 = 8%)
        uint256 totalValue;
        bool isDiscounted; // true for zero-coupon instruments
        bytes32 instrumentHash; // hash of legal documentation
    }

    function createVault(
        string calldata name,
        string calldata symbol,
        address asset,
        InstrumentInfo calldata info,
        uint256 epochStart,
        uint256 epochEnd,
        uint256 minInvestment
    ) external returns (address vault);

    function lockVault(address vault) external;
    function initiateSettlement(address vault) external;
    function processMaturity(address vault) external;
    function emergencyShutdown(address vault) external;

    event VaultCreated(address indexed vault, bytes32 indexed instrumentHash);
    event VaultLocked(address indexed vault);
    event SettlementInitiated(address indexed vault, uint256 amount);
    event MaturityProcessed(address indexed vault, uint256 returnAmount);
    event EmergencyShutdown(address indexed vault);
}
