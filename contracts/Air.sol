// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.1;

import "./erc20/ERC20Lockable.sol";
import "./erc20/ERC20Burnable.sol";
import "./erc20/ERC20Mintable.sol";
import "./library/Pausable.sol";
import "./library/Freezable.sol";

contract Air is ERC20Lockable, ERC20Burnable, ERC20Mintable, Freezable {
    using SafeMath for uint256;
    string private constant _name = "Airian";
    string private constant _symbol = "AIR";
    uint8 private constant _decimals = 18;
    uint256 private constant _initial_supply = 0;

    constructor() Ownable() {}

    function mint(address receiver, uint256 amount)
        external
        override
        onlyOwner
        whenNotPaused
        returns (bool success)
    {
        require(
            receiver != address(0),
            "ERC20Mintable/mint : Should not mint to zero address"
        );
        require(
            !_mintingFinished,
            "ERC20Mintable/mint : Cannot mint after finished"
        );
        require(
            _totalSupply.add(amount) <= (1_000_000_000 * (10**uint256(18))),
            "ERC20Mintable/mint  : Cannot mint more than cap"
        );
        _mint(receiver, amount);
        emit Mint(receiver, amount);
        success = true;
    }

    function transfer(address to, uint256 amount)
        external
        override
        whenNotFrozen(msg.sender)
        whenNotPaused
        checkLock(msg.sender, amount)
        returns (bool success)
    {
        require(
            to != address(0),
            "TAL/transfer : Should not send to zero address"
        );
        _transfer(msg.sender, to, amount);
        success = true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    )
        external
        override
        whenNotFrozen(from)
        whenNotPaused
        checkLock(from, amount)
        returns (bool success)
    {
        require(
            to != address(0),
            "TAL/transferFrom : Should not send to zero address"
        );
        _transfer(from, to, amount);
        _approve(
            from,
            msg.sender,
            _allowances[from][msg.sender].sub(
                amount,
                "TAL/transferFrom : Cannot send more than allowance"
            )
        );
        success = true;
    }

    function approve(address spender, uint256 amount)
        external
        override
        returns (bool success)
    {
        require(
            spender != address(0),
            "SAM/approve : Should not approve zero address"
        );
        _approve(msg.sender, spender, amount);
        success = true;
    }

    function name() external pure override returns (string memory tokenName) {
        tokenName = _name;
    }

    function symbol()
        external
        pure
        override
        returns (string memory tokenSymbol)
    {
        tokenSymbol = _symbol;
    }

    function decimals() external pure override returns (uint8 tokenDecimals) {
        tokenDecimals = _decimals;
    }
}
