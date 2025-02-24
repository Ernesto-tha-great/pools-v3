// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IEscrow.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/ILiquidityPool.sol";

/**
 * @title Escrow
 * @notice Handles secure fund transfers between pools and issuers
 */
contract Escrow is IEscrow {
    struct EscrowInfo {
        uint256 amount;
        address asset;
        bool isSettled;
        bool isMatured;
    }

    address public immutable manager;
    mapping(address => EscrowInfo) public poolEscrows;

    event EscrowCreated(address indexed pool, uint256 amount, address asset);
    event EscrowSettled(address indexed pool, address indexed issuer);
    event MaturitySettled(address indexed pool, uint256 amount);

    modifier onlyManager() {
        require(msg.sender == manager, "UNAUTHORIZED");
        _;
    }

    constructor(address _manager) {
        require(_manager != address(0), "ZERO_ADDRESS");
        manager = _manager;
    }

    function depositForSettlement(address pool, uint256 amount) external override {
        require(poolEscrows[pool].amount == 0, "ESCROW_EXISTS");

        address asset = ILiquidityPool(pool).asset();
        require(IERC20(asset).transferFrom(pool, address(this), amount), "TRANSFER_FAILED");

        poolEscrows[pool] = EscrowInfo({amount: amount, asset: asset, isSettled: false, isMatured: false});

        emit EscrowCreated(pool, amount, asset);
    }

    function releaseToIssuer(address pool, address issuer, uint256 amount) external override onlyManager {
        EscrowInfo storage escrow = poolEscrows[pool];
        require(!escrow.isSettled, "ALREADY_SETTLED");
        require(escrow.amount >= amount, "INSUFFICIENT_FUNDS");

        require(IERC20(escrow.asset).transfer(issuer, amount), "TRANSFER_FAILED");

        escrow.isSettled = true;
        emit EscrowSettled(pool, issuer);
    }

    function processMaturityPayment(address pool, uint256 principalPlusYield) external override onlyManager {
        EscrowInfo storage escrow = poolEscrows[pool];
        require(escrow.isSettled, "NOT_SETTLED");
        require(!escrow.isMatured, "ALREADY_MATURED");

        require(IERC20(escrow.asset).transferFrom(msg.sender, pool, principalPlusYield), "TRANSFER_FAILED");

        escrow.isMatured = true;
        emit MaturityProcessed(pool, principalPlusYield);
    }

    function getEscrowInfo(address pool)
        external
        view
        returns (uint256 amount, address asset, bool isSettled, bool isMatured)
    {
        EscrowInfo storage escrow = poolEscrows[pool];
        return (escrow.amount, escrow.asset, escrow.isSettled, escrow.isMatured);
    }

    // Emergency functions
    function emergencyReturn(address pool, address receiver) external onlyManager {
        EscrowInfo storage escrow = poolEscrows[pool];
        require(!escrow.isSettled, "ALREADY_SETTLED");

        uint256 amount = escrow.amount;
        escrow.amount = 0;
        require(IERC20(escrow.asset).transfer(receiver, amount), "TRANSFER_FAILED");
    }
}
