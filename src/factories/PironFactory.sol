// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IManager.sol";
import "../interfaces/ILiquidityPool.sol";

/**
 * @title MoneyMarketFactory
 * @notice Factory contract for deploying new money market vaults with minimal proxy pattern
 */
contract PironFactory {
    event PoolDeployed(address indexed pool, address indexed implementation);
    event ImplementationUpdated(address indexed oldImpl, address indexed newImpl);

    address public immutable manager;
    address public poolImplementation;

    mapping(address => bool) public isPoolDeployed;
    address[] public allPools;

    modifier onlyManager() {
        require(msg.sender == manager, "UNAUTHORIZED");
        _;
    }

    constructor(address _manager, address _implementation) {
        require(_manager != address(0) && _implementation != address(0), "ZERO_ADDRESS");
        manager = _manager;
        poolImplementation = _implementation;
    }

    /**
     * @notice Deploys a new vault using minimal proxy pattern
     * @param salt Unique salt for deterministic deployment
     */
    function deployPool(bytes32 salt) external onlyManager returns (address pool) {
        bytes memory creationCode = _getCreationCode(poolImplementation);

        assembly {
            pool := create2(0, add(creationCode, 32), mload(creationCode), salt)
        }

        require(pool != address(0), "DEPLOYMENT_FAILED");
        isPoolDeployed[pool] = true;
        allPools.push(pool);

        emit PoolDeployed(pool, poolImplementation);
    }

    /**
     * @notice Updates the vault implementation for future deployments
     * @param newImplementation New implementation address
     */
    function updateImplementation(address newImplementation) external onlyManager {
        require(newImplementation != address(0), "ZERO_ADDRESS");

        address oldImpl = poolImplementation;
        poolImplementation = newImplementation;

        emit ImplementationUpdated(oldImpl, newImplementation);
    }

    /**
     * @notice Generates minimal proxy creation code
     */
    function _getCreationCode(address implementation) internal pure returns (bytes memory) {
        bytes20 targetBytes = bytes20(implementation);

        // EIP-1167 minimal proxy pattern
        bytes memory code = new bytes(0x37);
        assembly {
            mstore(add(code, 0x20), 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(code, 0x34), targetBytes)
            mstore(add(code, 0x48), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
        }

        return code;
    }

    /**
     * @notice Gets all deployed vaults
     */
    function getAllPools() external view returns (address[] memory) {
        return allPools;
    }

    /**
     * @notice Computes the deterministic address for a vault before deployment
     */
    function computePoolAddress(bytes32 salt) external view returns (address) {
        bytes memory creationCode = _getCreationCode(poolImplementation);
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(creationCode)));
        return address(uint160(uint256(hash)));
    }
}
