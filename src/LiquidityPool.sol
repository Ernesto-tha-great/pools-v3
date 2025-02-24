// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IMoneyMarketVault.sol";
import "./utils/FixedPointMath.sol";

/**
 * @title MoneyMarketVault or liquidity pool
 * @notice ERC4626-compliant vault for money market instruments
 */
contract MoneyMarketVault is IMoneyMarketVault {
    using FixedPointMath for uint256;

    // State variables
    VaultStatus public override status;
    VaultInfo public override vaultInfo;
    address public manager;
    address public escrow;

    uint256 private _totalAssets;
    uint256 private _totalShares;

    mapping(address => uint256) private _shares;
    mapping(address => uint256) private _assets;

    // Modifiers
    modifier onlyManager() {
        require(msg.sender == manager, "UNAUTHORIZED");
        _;
    }

    modifier whenStatus(VaultStatus _status) {
        require(status == _status, "INVALID_STATUS");
        _;
    }

    function initialize(address _manager, address _escrow, VaultInfo calldata _info) external override {
        require(manager == address(0), "ALREADY_INITIALIZED");
        require(_manager != address(0) && _escrow != address(0), "ZERO_ADDRESS");

        manager = _manager;
        escrow = _escrow;
        vaultInfo = _info;
        status = VaultStatus.Active;
    }

    function asset() public view override returns (address) {
        return vaultInfo.asset;
    }

    function totalAssets() public view override returns (uint256) {
        return _totalAssets;
    }

    function convertToShares(uint256 assets) public view override returns (uint256) {
        uint256 supply = _totalShares;
        return supply == 0 ? assets : assets.mulDivDown(supply, _totalAssets);
    }

    function convertToAssets(uint256 shares) public view override returns (uint256) {
        uint256 supply = _totalShares;
        return supply == 0 ? shares : shares.mulDivDown(_totalAssets, supply);
    }

    function maxDeposit(address) public view override returns (uint256) {
        if (status != VaultStatus.Active) return 0;
        if (block.timestamp < vaultInfo.epochStart || block.timestamp > vaultInfo.epochEnd) return 0;
        return type(uint256).max;
    }

    function maxMint(address) public view override returns (uint256) {
        if (status != VaultStatus.Active) return 0;
        if (block.timestamp < vaultInfo.epochStart || block.timestamp > vaultInfo.epochEnd) return 0;
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        if (status != VaultStatus.Active) return 0;
        if (block.timestamp > vaultInfo.epochEnd) return 0;
        return convertToAssets(_shares[owner]);
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        if (status != VaultStatus.Active) return 0;
        if (block.timestamp > vaultInfo.epochEnd) return 0;
        return _shares[owner];
    }

    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view override returns (uint256) {
        return convertToAssets(shares);
    }

    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        return convertToShares(assets);
    }

    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return convertToAssets(shares);
    }

    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        require(assets >= vaultInfo.minInvestment, "BELOW_MIN_INVESTMENT");
        require(block.timestamp >= vaultInfo.epochStart, "EPOCH_NOT_STARTED");
        require(block.timestamp <= vaultInfo.epochEnd, "EPOCH_ENDED");
        require(status == VaultStatus.Active, "VAULT_NOT_ACTIVE");

        uint256 shares = previewDeposit(assets);

        // Transfer tokens
        IERC20(asset()).transferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);
        _assets[receiver] += assets;
        _totalAssets += assets;

        emit Deposit(msg.sender, receiver, assets, shares);
        return shares;
    }

    function mint(uint256 shares, address receiver) public override returns (uint256) {
        uint256 assets = previewMint(shares);
        require(assets >= vaultInfo.minInvestment, "BELOW_MIN_INVESTMENT");
        require(block.timestamp >= vaultInfo.epochStart, "EPOCH_NOT_STARTED");
        require(block.timestamp <= vaultInfo.epochEnd, "EPOCH_ENDED");
        require(status == VaultStatus.Active, "VAULT_NOT_ACTIVE");

        // Transfer tokens
        IERC20(asset()).transferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);
        _assets[receiver] += assets;
        _totalAssets += assets;

        emit Deposit(msg.sender, receiver, assets, shares);
        return assets;
    }

    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        require(status == VaultStatus.Active, "VAULT_NOT_ACTIVE");
        require(block.timestamp <= vaultInfo.epochEnd, "EPOCH_ENDED");

        uint256 shares = previewWithdraw(assets);

        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            require(shares <= allowed, "INSUFFICIENT_ALLOWANCE");
            _approve(owner, msg.sender, allowed - shares);
        }

        _burn(owner, shares);
        _assets[owner] -= assets;
        _totalAssets -= assets;

        IERC20(asset()).transfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        require(status == VaultStatus.Active, "VAULT_NOT_ACTIVE");
        require(block.timestamp <= vaultInfo.epochEnd, "EPOCH_ENDED");

        uint256 assets = previewRedeem(shares);

        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            require(shares <= allowed, "INSUFFICIENT_ALLOWANCE");
            _approve(owner, msg.sender, allowed - shares);
        }

        _burn(owner, shares);
        _assets[owner] -= assets;
        _totalAssets -= assets;

        IERC20(asset()).transfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        return assets;
    }

    // Manager functions
    function lockVault() external onlyManager whenStatus(VaultStatus.Active) {
        require(block.timestamp > vaultInfo.epochEnd, "EPOCH_NOT_ENDED");
        status = VaultStatus.Locked;
    }

    function initiateSettlement() external onlyManager whenStatus(VaultStatus.Locked) {
        IERC20(asset()).approve(escrow, _totalAssets);
        IEscrow(escrow).depositForSettlement(address(this), _totalAssets);
        status = VaultStatus.Settled;
    }

    function processMaturity(uint256 principalPlusYield) external onlyManager whenStatus(VaultStatus.Settled) {
        require(block.timestamp >= vaultInfo.maturityDate, "NOT_MATURED");
        status = VaultStatus.Matured;
        // Distribution logic will be handled by Manager
    }

    function emergencyShutdown() external onlyManager {
        require(status != VaultStatus.EmergencyShutdown, "ALREADY_SHUTDOWN");
        status = VaultStatus.EmergencyShutdown;
    }

    // Internal functions
    function _mint(address to, uint256 shares) internal {
        _shares[to] += shares;
        _totalShares += shares;
    }

    function _burn(address from, uint256 shares) internal {
        _shares[from] -= shares;
        _totalShares -= shares;
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        // Implementation of approve logic
    }

    // View functions
    function expectedReturn() external view override returns (uint256) {
        if (status != VaultStatus.Matured) {
            if (vaultInfo.isDiscounted) {
                return _calculateDiscountedReturn();
            } else {
                return _calculateCouponReturn();
            }
        }
        return 0;
    }

    function _calculateDiscountedReturn() internal view returns (uint256) {
        // Zero-coupon calculation
        uint256 daysToMaturity = (vaultInfo.maturityDate - block.timestamp) / 1 days;
        return _totalAssets.mulDivDown(vaultInfo.yieldRate, 10000) * daysToMaturity / 365;
    }

    function _calculateCouponReturn() internal view returns (uint256) {
        // Interest-bearing calculation
        uint256 daysToMaturity = (vaultInfo.maturityDate - block.timestamp) / 1 days;
        return _totalAssets.mulDivDown(vaultInfo.yieldRate, 10000) * daysToMaturity / 365;
    }

    // Additional helper functions
    function balanceOf(address account) public view returns (uint256) {
        return _shares[account];
    }

    function investedAmountOf(address account) public view returns (uint256) {
        return _assets[account];
    }

    function getVaultMetrics()
        external
        view
        returns (uint256 totalInvested, uint256 totalSharesMinted, uint256 currentYield, uint256 timeToMaturity)
    {
        totalInvested = _totalAssets;
        totalSharesMinted = _totalShares;
        currentYield = vaultInfo.yieldRate;
        timeToMaturity = block.timestamp >= vaultInfo.maturityDate ? 0 : vaultInfo.maturityDate - block.timestamp;
    }
}
