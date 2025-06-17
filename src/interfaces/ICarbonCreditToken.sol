// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface ICarbonCreditToken {
    /**
     * @dev Emitted when the protocol treasury address is changed.
     */
    event ProtocolTreasuryChanged(address indexed newTreasury);

    /**
     * @dev Emitted when tokens are transferred from the treasury.
     */
    event TreasuryTransfer(address indexed to, uint256 amount);

    /**
     * @dev Emitted when tokens are retired (burned) from the treasury.
     */
    event TreasuryRetirement(uint256 amount, string reason);

    /**
     * @dev Returns the address of the protocol treasury.
     */
    function protocolTreasury() external view returns (address);

    /**
     * @dev Mints a specified amount of tokens directly to the protocol treasury.
     * MUST only be callable by the MINTER_ROLE.
     * @param amount The amount of tokens to mint.
     */
    function mintToTreasury(uint256 amount) external;

    /**
     * @dev Mints `amount` tokens and sends them to a specified `to` address.
     * MUST only be callable by the MINTER_ROLE.
     * @param to The address to mint tokens to.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external;

    /**
     * @dev Transfers tokens from the treasury to a specified address.
     * MUST only be callable by the TREASURY_MANAGER_ROLE.
     * @param to The recipient address.
     * @param amount The amount to transfer.
     */
    function transferFromTreasury(address to, uint256 amount) external;

    /**
     * @dev Retires (burns) tokens from the treasury.
     * Used to permanently remove carbon credits from circulation after use.
     * MUST only be callable by the TREASURY_MANAGER_ROLE.
     * @param amount The amount to retire.
     * @param reason A string describing the reason for retirement.
     */
    function retireFromTreasury(uint256 amount, string calldata reason) external;
}
