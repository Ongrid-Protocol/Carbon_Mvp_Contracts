// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ICarbonCreditToken} from "../interfaces/ICarbonCreditToken.sol";
import {Errors} from "../common/Errors.sol";

/**
 * @title Carbon Credit Token
 * @dev ERC20 token representing OnGrid Carbon Credits (tonnes of CO2e avoided).
 * Minting is controlled by the MINTER_ROLE (intended for EnergyDataBridge).
 * Tokens are initially minted to a designated Protocol Treasury.
 * The contract is pausable and upgradeable using the UUPS proxy pattern.
 */
contract CarbonCreditToken is
    ICarbonCreditToken,
    ERC20,
    ERC20Burnable, // Includes Ownable, inheriting separately for explicitness below
    AccessControl,
    Pausable,
    UUPSUpgradeable
{
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant TREASURY_MANAGER_ROLE = keccak256("TREASURY_MANAGER_ROLE");

    address public protocolTreasury;

    /**
     * @dev Modifier to check if the caller has the MINTER_ROLE.
     */
    modifier onlyMinter() {
        if (!hasRole(MINTER_ROLE, _msgSender())) revert Errors.CallerNotMinter();
        _;
    }

    /**
     * @dev Modifier to check if the caller has the TREASURY_MANAGER_ROLE.
     */
    modifier onlyTreasuryManager() {
        if (!hasRole(TREASURY_MANAGER_ROLE, _msgSender())) revert Errors.CallerNotTreasuryManager();
        _;
    }

    /**
     * @dev Sets up the contract, initializes ERC20 details, AccessControl roles, and treasury.
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     * @param _initialAdmin The address to grant DEFAULT_ADMIN_ROLE, PAUSER_ROLE, and UPGRADER_ROLE.
     * @param _protocolTreasury The address of the protocol treasury.
     */
    constructor(string memory name, string memory symbol, address _initialAdmin, address _protocolTreasury)
        ERC20(name, symbol)
    {
        if (_initialAdmin == address(0)) revert Errors.ZeroAddress();
        if (_protocolTreasury == address(0)) revert Errors.ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        _grantRole(PAUSER_ROLE, _initialAdmin);
        _grantRole(UPGRADER_ROLE, _initialAdmin);
        _grantRole(TREASURY_MANAGER_ROLE, _initialAdmin);
        // MINTER_ROLE is granted separately, typically to the EnergyDataBridge contract

        protocolTreasury = _protocolTreasury;
        emit ProtocolTreasuryChanged(_protocolTreasury); // Emit event for initial setting
    }

    /**
     * @dev Sets the address of the protocol treasury where minted tokens are sent.
     * Can only be called by the DEFAULT_ADMIN_ROLE.
     * @param _newTreasury The new address for the protocol treasury.
     */
    function setProtocolTreasury(address _newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newTreasury == address(0)) revert Errors.ZeroAddress();
        protocolTreasury = _newTreasury;
        emit ProtocolTreasuryChanged(_newTreasury);
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * Fixed to 3 as specified.
     */
    function decimals() public pure override returns (uint8) {
        return 3;
    }

    /**
     * @dev Mints `amount` tokens and sends them to the `protocolTreasury`.
     * Requires the caller to have the MINTER_ROLE.
     * Operation is paused if the contract is paused.
     * Emits a {Transfer} event with `from` set to the zero address.
     * @param amount The amount of tokens to mint.
     */
    function mintToTreasury(uint256 amount) external virtual whenNotPaused onlyMinter {
        _mint(protocolTreasury, amount);
    }

    /**
     * @dev Transfers tokens from the treasury to a specified address.
     * Can only be called by addresses with TREASURY_MANAGER_ROLE.
     * @param to The recipient address.
     * @param amount The amount to transfer.
     */
    function transferFromTreasury(address to, uint256 amount) external virtual whenNotPaused onlyTreasuryManager {
        if (to == address(0)) revert Errors.ZeroAddress();
        if (amount == 0) revert Errors.InvalidAmount(amount);

        _transfer(protocolTreasury, to, amount);
        emit TreasuryTransfer(to, amount);
    }

    /**
     * @dev Retires (burns) tokens from the treasury.
     * Used to permanently remove carbon credits from circulation after use.
     * Can only be called by addresses with TREASURY_MANAGER_ROLE.
     * @param amount The amount to retire.
     * @param reason A string describing the reason for retirement.
     */
    function retireFromTreasury(uint256 amount, string calldata reason)
        external
        virtual
        whenNotPaused
        onlyTreasuryManager
    {
        if (amount == 0) revert Errors.InvalidAmount(amount);

        // First transfer to this contract, then burn
        _transfer(protocolTreasury, address(this), amount);
        _burn(address(this), amount);

        emit TreasuryRetirement(amount, reason);
    }

    /**
     * @dev Pauses all token transfers, minting, and burning.
     * Requires the caller to have the PAUSER_ROLE.
     */
    function pause() external virtual onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses the token transfers, minting, and burning.
     * Requires the caller to have the PAUSER_ROLE.
     */
    function unpause() external virtual onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes minting and burning.
     * Makes transfers pausable.
     */
    function _update(address from, address to, uint256 value) internal override(ERC20) {
        super._update(from, to, value);
    }

    /**
     * @dev Authorizes an upgrade for the UUPS pattern.
     * Requires the caller to have the UPGRADER_ROLE.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
