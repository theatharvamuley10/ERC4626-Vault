// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

interface IERC20 {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                            METADATA METHODS
    //////////////////////////////////////////////////////////////*/
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    /*//////////////////////////////////////////////////////////////
                            ERC20 METHODS
    //////////////////////////////////////////////////////////////*/
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /*//////////////////////////////////////////////////////////////
                           EIP-2612 METHODS
    //////////////////////////////////////////////////////////////*/
    function nonces(address owner) external view returns (uint256);

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;

    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
