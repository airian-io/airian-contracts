// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.1;

import "./ERC20.sol";
import "../library/Pausable.sol";

abstract contract ERC20Mintable is ERC20, Pausable {
    event Mint(address indexed receiver, uint256 amount);
    event MintFinished();

    bool internal _mintingFinished;
    ///@notice mint token
    ///@dev only owner can call this function
    function mint(address receiver, uint256 amount)
        virtual
        external
        returns (bool success);

    ///@notice finish minting, cannot mint after calling this function
    ///@dev only owner can call this function
    function finishMint()
        external
        onlyOwner
        returns (bool success)
    {
        require(
            !_mintingFinished,
            "ERC20Mintable/finishMinting : Already finished"
        );
        _mintingFinished = true;
        emit MintFinished();
        return true;
    }

    function isFinished() external view returns(bool finished) {
        finished = _mintingFinished;
    }
}
