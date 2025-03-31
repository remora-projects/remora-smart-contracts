// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import {IERC20} from "../IERC20.sol";
import {RemoraRWABurnable} from "./RemoraRWABurnable.sol";
import {RemoraRWALockUp} from "./RemoraRWALockUp.sol";
import {RemoraRWAHolderManagement} from "./RemoraRWAHolderManagement.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface IAllowlist {
    function exchangeAllowed(address, address) external view;
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
    UUPSUpgradeable,
    ERC20PermitUpgradeable,
    PausableUpgradeable,
    RemoraRWABurnable,
    RemoraRWALockUp,
    RemoraRWAHolderManagement
{
    /// @dev The flat fee for token transfers, 6 decimals USD
    uint32 transferFee;
    /// @dev The price per token paid out when burned, 6 decimals USD
    uint64 pricePerBurnedToken;
    /// @dev Reference to the external allowlist contract for managing user permissions.
    IAllowlist private _allowlist;
    /// @dev saving space for future implementations
    address[2] __gap;
    /// @dev Mapping that contains addresses that are able to send and recieve tokens without a fee
    mapping(address => bool) private _whitelist;

    /**
     * @notice Event emitted when flat fee has changed.
     * @param newFee Value of the new fee.
     */
    event TransferFeeChanged(uint32 newFee);

    /**
     * @notice Event emitted when a value for the burned token is set
     * @param price The price that will be paid out per burned token
     */
    event NewPricePerBurnedToken(uint64 price);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the RWA token contract with specified parameters.
     * @param tokenOwner The initial owner of the tokens, must be on allowList.
     * @param initialAuthority The address granted initial access management authority.
     * @param allowList The address of the allowlist contract.
     * @param stablecoin The address of the stablecoin used for payouts.
     * @param wallet The address of the wallet to withdraw contract funds.
     * @param _name The name of the token.
     * @param _symbol The symbol of the token.
     * @param _initialSupply The initial supply of tokens, in whole units.
     */
    function initialize(
        address tokenOwner,
        address initialAuthority,
        address allowList,
        address stablecoin,
        address wallet,
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply
    ) public initializer {
        __ERC20_init(_name, _symbol);
        __ERC20Permit_init(_name);
        __Pausable_init();
        __RemoraBurnable_init();
        __RemoraLockUp_init(0); //start with 0 lock up time
        __RemoraHolderManagement_init(
            initialAuthority,
            stablecoin,
            wallet,
            0 //starts at zero, will need to update it later
        );
        __UUPSUpgradeable_init();

        _allowlist = IAllowlist(allowList);
        _whitelist[tokenOwner] = true; //whitelist owner to be able to send tokens freely
        _mint(tokenOwner, _initialSupply * 10 ** decimals());
    }

    function setLockUpTime(uint32 newLockUpTime) external restricted {
        _setLockUpTime(newLockUpTime);
    }

    /**
     * @notice Adds address to whitelist
     * @param addrToAdd The address to add
     */
    function addToWhitelist(address addrToAdd) external restricted {
        if (addrToAdd == address(0)) revert InvalidAddress();
        _whitelist[addrToAdd] = true;
    }

    /**
     * @notice Removes address from whitelist
     * @param addrToRemove The address to remove
     */
    function removeFromWhitelist(address addrToRemove) external restricted {
        if (addrToRemove == address(0)) revert InvalidAddress();
        _whitelist[addrToRemove] = false;
    }

    /**
     * @notice Sets new transfer fee.
     * @param newFee New transfer fee value, in USD, 6 decimals.
     */
    function setTransferFee(uint32 newFee) external restricted {
        transferFee = newFee;
        emit TransferFeeChanged(newFee);
    }

    /**
     * @notice Allows token holders to claim payout when conditions allow.
     * @dev Enforces stablecoin payout with flat fee set in holder management.
     */
    function claimPayout() external whenNotPaused nonReentrant {
        _claimPayout(_msgSender(), true, false, 0);
    }

    /**
     * @notice Function that allows restricted accounts to change the way pay out is collected.
     * @param investor Address of the investor collecting payout.
     * @param useStablecoin Value indicating whether to pay out in stablecoin or not.
     * @param useCustomFee Value indicating whether or not to use a custom fee.
     * @param feeValue The custom fee to use if useCustomFee is true.
     */
    function adminClaimPayout(
        address investor,
        bool useStablecoin,
        bool useCustomFee,
        uint256 feeValue
    ) external restricted nonReentrant {
        _claimPayout(investor, useStablecoin, useCustomFee, feeValue);
    }

    /**
     * @notice Allows restricted accounts to transfer tokens without fee, pausing, freezing, or allowlist restrictions.
     * @dev Calls OpenZeppelin ERC20Upgradeable transferFrom function.
     * @param from The address from which tokens are being transferred.
     * @param to The recipient address.
     * @param value The number of tokens to transfer.
     * @param checkTC Whether or not to check if the user tokens are being sent to have signed the T&C
     * @param enforceLock Whether or not to enforce token locking mechanism
     * @return A boolean indicating whether the transfer succeeded or not.
     */
    function adminTransferFrom(
        address from,
        address to,
        uint256 value,
        bool checkTC,
        bool enforceLock
    ) external restricted returns (bool) {
        if (checkTC && !hasSignedTC(to)) revert TermsAndConditionsNotSigned(to);

        if (!_whitelist[from]) _unlockTokens(from, value, !enforceLock);
        if (enforceLock && !_whitelist[to]) _lockTokens(to, value);

        HolderManagementStorage storage $ = _getHolderManagementStorage();
        if (
            $._holderStatus[from].isFrozen &&
            block.timestamp > $._holderStatus[from].frozenTimestamp + 30 days
        ) {
            super._transfer(from, to, value);
            return true;
        }
        return super.transferFrom(from, to, value);
    }

    /**
     * @notice Updates the address of the allowlist contract. Restricted to authorized accounts.
     * @param newImplementation The new allowlist contract address.
     */
    function updateAllowList(address newImplementation) external restricted {
        require(newImplementation != address(0));
        _allowlist = IAllowlist(newImplementation);
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
     * @notice Enables the burning of tokens and sets value for how much is paid out per burned token. Restricted to authorized accounts.
     * @param changePrice Whether or not the burnPrice will be changing
     * @param burnPrice The price that will be paid out per burned token.
     */
    function enableBurning(
        bool changePrice,
        uint64 burnPrice
    ) external restricted {
        _enableBurning();
        if (changePrice) {
            pricePerBurnedToken = burnPrice;
            emit NewPricePerBurnedToken(burnPrice);
        }
    }

    /**
     * @notice Disables the burning of tokens. Restricted to authorized accounts.
     */
    function disableBurning() external restricted {
        _disableBurning();
    }

    /**
     * @notice Transfers tokens to a recipient if allowed, with flat fee.
     * @dev Calls OpenZeppelin ERC20Upgradeable transfer function
     * @param to The recipient address.
     * @param value The number of tokens to transfer.
     * @return result A boolean indicating whether the transfer succeeded or not.
     */
    function transfer(
        address to,
        uint256 value
    ) public override whenNotPaused nonReentrant returns (bool result) {
        address sender = _msgSender();
        _exchangeAllowed(sender, to);

        bool fromWL = _whitelist[sender];
        bool toWL = _whitelist[to];

        if (!fromWL) _unlockTokens(sender, value, false);
        if (!toWL) _lockTokens(to, value);

        result = super.transfer(to, value);

        uint256 _transferFee = transferFee;
        if (_transferFee != 0 && !fromWL && !toWL) {
            HolderManagementStorage storage $ = _getHolderManagementStorage();
            IERC20 stablecoin = $._stablecoin;
            uint8 numDecimals = $._stablecoinDecimals;
            if (numDecimals != 6) {
                _transferFee *= 10 ** (numDecimals - 6);
            }
            stablecoin.transferFrom(sender, $._wallet, _transferFee);
        }
    }

    /**
     * @notice Transfers tokens from one address to another using an allowance. Sender pays fee.
     * @dev Calls OpenZeppelin ERC20Upgradeable transferFrom function.
     * @param from The address from which tokens are being transferred.
     * @param to The recipient address.
     * @param value The number of tokens to transfer.
     * @return result A boolean indicating whether the transfer succeeded or not.
     */
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public override whenNotPaused nonReentrant returns (bool result) {
        _exchangeAllowed(from, to);

        address sender = _msgSender();
        bool fromWL = _whitelist[from];
        bool toWL = _whitelist[to];

        if (!fromWL) _unlockTokens(from, value, false);
        if (!toWL) _lockTokens(to, value);

        result = super.transferFrom(from, to, value);

        uint256 _transferFee = transferFee;
        if (_transferFee != 0 && !_whitelist[sender] && !fromWL && !toWL) {
            HolderManagementStorage storage $ = _getHolderManagementStorage();
            IERC20 stablecoin = $._stablecoin;
            uint8 numDecimals = $._stablecoinDecimals;
            if (numDecimals != 6) {
                _transferFee *= 10 ** (numDecimals - 6);
            }
            stablecoin.transferFrom(sender, $._wallet, _transferFee);
        }
    }

    /**
     * @notice Burns a number of tokens from the sender, and pays out in stablecoin.
     * @param amount The amount of tokens to burn.
     */
    function burn(uint256 amount) public whenBurnable whenNotPaused {
        address sender = _msgSender();
        if (isHolderFrozen(sender)) revert UserIsFrozen(sender);

        uint256 burnPayout = amount * pricePerBurnedToken;
        _burn(sender, amount);

        HolderManagementStorage storage $ = _getHolderManagementStorage();
        IERC20 stablecoin = $._stablecoin;
        uint256 stablecoinBalance = stablecoin.balanceOf(address(this));

        uint8 numDecimals = $._stablecoinDecimals;
        if (numDecimals != 6) burnPayout *= 10 ** (numDecimals - 6);
        if (burnPayout > stablecoinBalance) {
            revert InsufficentStablecoinBalance();
        }

        stablecoin.transfer(sender, burnPayout);
    }

    /**
     * @notice Burns tokens from a specified account. Restricted to authorized accounts.
     * @param account The address whose tokens will be burned.
     * @param value The number of tokens to burn.
     */
    function burnFrom(
        address account,
        uint256 value
    ) public whenBurnable restricted {
        _burnFrom(account, value);
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
     * @notice Authorizes an upgrade to a new contract implementation.
     * Restricted to authorized accounts only.
     * @param newImplementation The address of the new contract implementation.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override restricted {}

    /**
     * @notice Updates internal state during token transfers, including holder management.
     * @param from The sender address.
     * @param to The recipient address.
     * @param value The number of tokens transferred.
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        super._update(from, to, value);
        _updateHolders(from, to);
    }

    /**
     * @notice Verifies if a token exchange between two addresses is allowed.
     * @param from The sender address.
     * @param to The recipient address.
     */
    function _exchangeAllowed(address from, address to) private view {
        _allowlist.exchangeAllowed(from, to);
        if (isHolderFrozen(from)) revert UserIsFrozen(from);
        if (isHolderFrozen(to)) revert UserIsFrozen(to);
        if (!hasSignedTC(to) && !_whitelist[to])
            revert TermsAndConditionsNotSigned(to);
    }
}
