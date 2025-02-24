// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IManager.sol";
import "./interfaces/ILiquidityPool.sol";
import "./interfaces/IEscrow.sol";
import "./LiquidityPool.sol";

/**
 * @title Manager
 * @notice Manages the lifecycle of money market pools and their instruments
 */
contract Manager is IManager {
    // Events
    event PoolStatusUpdated(address indexed pool, ILiquidityPool.PoolStatus status);
    event InstrumentRegistered(bytes32 indexed instrumentHash, InstrumentType iType);
    event SettlementProcessed(address indexed pool, address indexed issuer, uint256 amount);
    event MaturityCompleted(address indexed pool, uint256);
    event PoolCreated(address indexed pool, bytes32 indexed instrumentHash);
    event PoolLocked(address indexed pool);
    event SettlementInitiated(address indexed pool, uint256 amount);
    event EmergencyShutdown(address indexed pool);
    event MaturityProcessed(address indexed pool, uint256 amount);

    // State variables
    address public immutable escrow;
    address public immutable poolImplementation;

    mapping(address => bool) public isRegisteredPool;
    mapping(bytes32 => bool) public isRegisteredInstrument;
    mapping(address => address) public poolToIssuer;

    // Access control
    address public admin;
    mapping(address => bool) public isOperator;

    modifier onlyAdmin() {
        require(msg.sender == admin, "UNAUTHORIZED");
        _;
    }

    modifier onlyOperator() {
        require(isOperator[msg.sender], "UNAUTHORIZED");
        _;
    }

    constructor(address _escrow, address _poolImplementation) {
        require(_escrow != address(0) && _poolImplementation != address(0), "ZERO_ADDRESS");
        escrow = _escrow;
        poolImplementation = _poolImplementation;
        admin = msg.sender;
        isOperator[msg.sender] = true;
    }

    function createPool(
        string calldata name,
        string calldata symbol,
        address asset,
        InstrumentInfo calldata info,
        uint256 epochStart,
        uint256 epochEnd,
        uint256 minInvestment
    ) external override onlyOperator returns (address pool) {
        require(!isRegisteredInstrument[info.instrumentHash], "INSTRUMENT_EXISTS");
        require(epochStart > block.timestamp, "INVALID_START");
        require(epochEnd > epochStart, "INVALID_END");
        require(info.maturityDate > epochEnd, "INVALID_MATURITY");

        // Deploy new pool using create2 for deterministic addresses
        bytes32 salt = keccak256(abi.encodePacked(info.instrumentHash, block.timestamp));
        pool = _deployPool(salt);

        // Initialize pool
        ILiquidityPool(pool).initialize(
            address(this),
            escrow,
            ILiquidityPool.PoolInfo({
                name: name,
                symbol: symbol,
                asset: asset,
                epochStart: epochStart,
                epochEnd: epochEnd,
                maturityDate: info.maturityDate,
                minInvestment: minInvestment,
                yieldRate: info.yieldRate,
                isDiscounted: info.isDiscounted,
                instrumentHash: info.instrumentHash
            })
        );

        // Register pool and instrument
        isRegisteredPool[pool] = true;
        isRegisteredInstrument[info.instrumentHash] = true;
        poolToIssuer[pool] = info.issuer;

        emit PoolCreated(pool, info.instrumentHash);
        emit InstrumentRegistered(info.instrumentHash, info.iType);
    }

    function lockPool(address pool) external override onlyOperator {
        require(isRegisteredPool[pool], "UNREGISTERED_POOL");

        ILiquidityPool(pool).lockPool();
        emit PoolLocked(pool);
    }

    function initiateSettlement(address pool) external override onlyOperator {
        require(isRegisteredPool[pool], "UNREGISTERED_POOL");

        // First lock the pool if not already locked
        if (ILiquidityPool(pool).status() == ILiquidityPool.PoolStatus.Active) {
            ILiquidityPool(pool).lockPool();
        }

        // Initiate settlement
        ILiquidityPool(pool).initiateSettlement();

        // Release funds to issuer
        address issuer = poolToIssuer[pool];
        uint256 amount = ILiquidityPool(pool).totalAssets();
        IEscrow(escrow).releaseToIssuer(pool, issuer, amount);

        emit SettlementInitiated(pool, amount);
    }

    function processMaturity(address pool) external override onlyOperator {
        require(isRegisteredPool[pool], "UNREGISTERED_POOL");
        require(ILiquidityPool(pool).status() == ILiquidityPool.PoolStatus.Settled, "NOT_SETTLED");

        ILiquidityPool.PoolInfo memory info = ILiquidityPool(pool).poolInfo();
        require(block.timestamp >= info.maturityDate, "NOT_MATURED");

        uint256 principalPlusYield = _calculateMaturityAmount(pool);

        // Process maturity payment through escrow
        IEscrow(escrow).processMaturityPayment(pool, principalPlusYield);

        // Update poolstatus
        ILiquidityPool(pool).processMaturity(principalPlusYield);

        emit MaturityProcessed(pool, principalPlusYield);
    }

    function emergencyShutdown(address pool) external override onlyAdmin {
        require(isRegisteredPool[pool], "UNREGISTERED_POOL");

        ILiquidityPool(pool).emergencyShutdown();
        emit EmergencyShutdown(pool);
    }

    // Internal functions
    function _deployPool(bytes32 salt) internal returns (address pool) {
        // Deploy new pool using create2
        bytes memory creationCode = type(LiquidityPool).creationCode;
        assembly {
            pool := create2(0, add(creationCode, 32), mload(creationCode), salt)
        }
        require(pool != address(0), "DEPLOYMENT_FAILED");
    }

    function _calculateMaturityAmount(address pool) internal view returns (uint256) {
        ILiquidityPool.PoolInfo memory info = ILiquidityPool(pool).poolInfo();
        uint256 principal = ILiquidityPool(pool).totalAssets();

        if (info.isDiscounted) {
            // For zero-coupon instruments
            return principal + (principal * info.yieldRate * (info.maturityDate - info.epochEnd) / (365 days * 10000));
        } else {
            // For interest-bearing instruments
            return principal + (principal * info.yieldRate * (info.maturityDate - info.epochEnd) / (365 days * 10000));
        }
    }

    // Admin functions
    function addOperator(address operator) external onlyAdmin {
        isOperator[operator] = true;
    }

    function removeOperator(address operator) external onlyAdmin {
        isOperator[operator] = false;
    }

    function transferAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "ZERO_ADDRESS");
        admin = newAdmin;
    }

    // View functions
    function getPoolInfo(address pool)
        external
        view
        returns (
            ILiquidityPool.PoolInfo memory info,
            ILiquidityPool.PoolStatus status,
            address issuer,
            uint256 totalAssets
        )
    {
        require(isRegisteredPool[pool], "UNREGISTERED_POOL");

        info = ILiquidityPool(pool).poolInfo();
        status = ILiquidityPool(pool).status();
        issuer = poolToIssuer[pool];
        totalAssets = ILiquidityPool(pool).totalAssets();
    }
}
