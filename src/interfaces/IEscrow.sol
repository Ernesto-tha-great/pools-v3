// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEscrow {
    function depositForSettlement(address vault, uint256 amount) external;
    function releaseToIssuer(address vault, address issuer, uint256 amount) external;
    function processMaturityPayment(address vault, uint256 principalPlusYield) external;

    event FundsDeposited(address indexed vault, uint256 amount);
    event FundsReleased(address indexed vault, address indexed issuer, uint256 amount);
    event MaturityProcessed(address indexed vault, uint256 amount);
}
