// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import {RemoraRWAPayOut} from "./RemoraPayOut.sol";
import {RemoraRWABurnable} from "./RemoraBurn.sol";
import {AccessManagedUpgradeable} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface RemoraAllowlist {
    function exchangeAllowed(address, address) external view returns (address);
}

/// @custom:security-contact support@remora.us
/**
 * @title RemoraRWAToken
 * @notice This contract represents a Real-World Asset (RWA) token, allowing tokenized representation of physical assets.
 * It incorporates features for managing transfers, minting, burning, allowlist checks, payouts, allowance permitting, and pausing.
 * The token operates with OpenZeppelin upgradeable contracts and custom modules for RWA-specific operations.
 */        
contract RemoraRWAToken is 
    Initializable, 
    ERC20Upgradeable, 
    ERC20PermitUpgradeable, 
    AccessManagedUpgradeable, 
    RemoraRWABurnable, 
    RemoraRWAPayOut,
    UUPSUpgradeable
{
    /// @dev Reference to the external allowlist contract for managing user permissions.
    RemoraAllowlist private _allowlist;

    /**
     * @notice Error emitted when an unregistered user attempts an operation requiring allowlist membership.
     * @param user The address of the unregistered user.
     */
    error UserNotRegistered(address user);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the RWA token contract with specified parameters.
     * @param tokenOwner The initial owner of the tokens.
     * @param initialAuthority The address granted initial access management authority.
     * @param _name The name of the token.
     * @param _symbol The symbol of the token.
     * @param _initialSupply The initial supply of tokens, in whole units.
     * @param allowList The address of the allowlist contract.
     * @param stablecoin The address of the stablecoin used for payouts.
     * @param wallet The address of the wallet to withdraw contract funds.
     * @param feePercentage The fee percentage for payouts.
     */
    function initialize(
        address tokenOwner,
        address initialAuthority,
        string memory _name, 
        string memory _symbol, 
        uint256 _initialSupply, 
        address allowList, 
        address stablecoin, 
        address wallet, 
        uint256 feePercentage
    ) initializer public {
        __ERC20_init(_name, _symbol);
        __ERC20Permit_init(_name);
        __AccessManaged_init(initialAuthority);
        __Pausable_init();
        __RemoraBurnable_init();
        __RemoraPayout_init(stablecoin, wallet, feePercentage);
        __UUPSUpgradeable_init();

        _allowlist = RemoraAllowlist(allowList);
        
        _mint(tokenOwner, _initialSupply * 10 ** decimals());
    }

    /**
     * @notice Defines the number of decimal places for the token. 
     * RWA tokens are non-fractional and operate in whole units only.
     * @return The number of decimals (always `0`).
     */
    function decimals() public pure override returns (uint8) {
        return 0;
    }

    /**
     * @notice Transfers tokens to a specified address. Restricted to authorized accounts.
     * @param to The recipient address.
     * @param value The number of tokens to transfer.
     * @return A boolean indicating whether the transfer succeeded.
     */
    function transfer(address to, uint256 value) public override whenNotPaused restricted returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, value);
        return true;
    }

    /**
     * @notice Transfers tokens from one address to another using an allowance. Restricted to authorized accounts.
     * @param from The address from which tokens are being transferred.
     * @param to The recipient address.
     * @param value The number of tokens to transfer.
     * @return A boolean indicating whether the transfer succeeded.
     */
    function transferFrom(address from, address to, uint256 value) public override whenNotPaused restricted returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    /**
     * @notice Mints new tokens. Restricted to authorized accounts.
     * @param to The recipient address.
     * @param amount The number of tokens to mint.
     */
    function mint(address to, uint256 amount) external restricted {
        _mint(to, amount);
    }

    /**
     * @notice Pauses all token transfers, burning, and rent collection. Restricted to authorized accounts.
     */
    function pause() external restricted {
        _pause();
    }

    /**
     * @notice Unpauses all token transfers, burning, and rent collection. Restricted to authorized accounts.
     */
    function unpause() external restricted {
        _unpause();
    }

    /**
     * @notice Enables the burning of tokens. Restricted to authorized accounts.
     */
    function enableBurning() external restricted {
        _enableBurning();
    }

    /**
     * @notice Disables the burning of tokens. Restricted to authorized accounts.
     */
    function disableBurning() external restricted {
        _disableBurning();
    }

    /**
     * @notice Burns tokens from a specified account. Restricted to authorized accounts.
     * @param account The address whose tokens will be burned.
     * @param value The number of tokens to burn.
     */
    function burnFrom(address account, uint256 value) public restricted {
        _burnFrom(account, value);
    }

    /**
     * @notice Updates the address of the allowlist contract. Restricted to authorized accounts.
     * @param newImplementation The new allowlist contract address.
     */
    function updateAllowList(address newImplementation) external restricted {
        require(newImplementation != address(0));
        _allowlist = RemoraAllowlist(newImplementation);
    }

    /**
     * @notice Verifies if a token exchange between two addresses is allowed.
     * @param from The sender address.
     * @param to The recipient address.
     */
    function _exchangeAllowed(address from, address to) internal nonReentrant {
        address res = _allowlist.exchangeAllowed(from, to);
        if(res != address(0)) revert UserNotRegistered(res);
    }

    /**
     * @notice Changes the stablecoin used for payouts. Restricted to authorized accounts.
     * @param stablecoin The address of the new stablecoin.
     */
    function changeStablecoin(address stablecoin) external restricted {
        _changeStablecoin(stablecoin);
    }

    /**
     * @notice Changes the withdrawal wallet address. Restricted to authorized accounts.
     * @param wallet The new wallet address.
     */
    function changeWallet(address wallet) external restricted {
        _changeWallet(wallet);
    }

    /**
     * @notice Distributes rental payments to token holders. Restricted to authorized accounts.
     * @param rentAmount The total amount to distribute.
     */
    function distributeRentalPayments(uint256 rentAmount) external restricted {
        _distributeRentalPayments(rentAmount);
    }

    /**
     * @notice Withdraws stablecoin funds held by the contract. Restricted to authorized accounts.
     */
    function withdraw() external restricted {
        _withdraw();
    }

    /**
     * @notice Authorizes an upgrade to a new contract implementation. Restricted to authorized accounts.
     * @param newImplementation The address of the new contract implementation.
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        restricted
        override
    {}

    /**
     * @notice Updates internal state during token transfers, including allowlist checks and holder management.
     * @param from The sender address.
     * @param to The recipient address.
     * @param value The number of tokens transferred.
     */
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable)
    {
        _exchangeAllowed(from, to); //allowlist
        super._update(from, to, value);  //erc20 
        _addHolder(to);
        _removeHolder(from);
    }
}