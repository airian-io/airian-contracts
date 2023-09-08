// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";

contract WhiteListNFT is
    ERC721,
    ERC721Enumerable,
    ERC721URIStorage,
    Pausable,
    Ownable,
    AccessControl,
    ERC721Burnable
{
    using Counters for Counters.Counter;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    Counters.Counter private _tokenIdCounter;

    // To support Klaytn network
    bytes4 private constant _INTERFACE_ID_KIP17 = 0x80ac58cd;

    bool public soulbound = false;
    bool public onetime = false;

    address public staking;

    struct WhiteList {
        address[] list;
        bool minted;
    }
    mapping(uint256 => WhiteList) public whitelist;

    event Grant(address, string);
    event SetStaking(address);
    event AddWhitelist(uint32, uint32);

    constructor(
        string memory name,
        string memory symbol,
        bool _soulbound,
        bool _onetime
    ) ERC721(name, symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);

        soulbound = _soulbound;
        onetime = _onetime;
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function addMinter(address minter) public onlyOwner {
        _grantRole(MINTER_ROLE, minter);
        emit Grant(minter, "MINTER_ROLE");
    }

    function addPauser(address pauser) public onlyOwner {
        _grantRole(PAUSER_ROLE, pauser);
        emit Grant(pauser, "PAUSER_ROLE");
    }

    function safeMint(address to, string memory uri)
        public
        virtual
        onlyRole(MINTER_ROLE)
        returns (uint256)
    {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        return tokenId;
    }

    function safeBatchMint(address to, string[] memory uris)
        public
        virtual
        onlyRole(MINTER_ROLE)
    {
        for (uint256 i = 0; i < uris.length; i++) {
            safeMint(to, uris[i]);
        }
    }

    function safeBatchMintLight(
        address to,
        string memory uri,
        uint256 amount
    ) public virtual onlyRole(MINTER_ROLE) {
        for (uint256 i = 0; i < amount; i++) {
            safeMint(to, uri);
        }
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId);

        if (soulbound == true) {
            if (
                // Allow staking
                to != staking &&
                // Allow unstaking
                from != staking &&
                // allow burn
                to != address(0) &&
                keccak256(abi.encodePacked(to)) !=
                keccak256("0x000000000000000000000000000000000000dEaD") &&
                // Allow mint
                from != address(0)
            ) {
                revert("soulbound NFT");
            }
        }
    }

    // The following functions are overrides required by Solidity.

    function _burn(uint256 tokenId)
        internal
        override(ERC721, ERC721URIStorage)
    {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        // To support Klaytn network
        return
            interfaceId == _INTERFACE_ID_KIP17 ||
            super.supportsInterface(interfaceId);
    }

    function setStaking(address _staking) public onlyOwner {
        staking = _staking;

        emit SetStaking(staking);
    }

    function addWhitelist(address[] calldata _whitelist, uint256 round)
        public
        onlyOwner
    {
        require(whitelist[round].minted == false, "already minted");

        for (uint256 i = 0; i < _whitelist.length; i++) {
            whitelist[round].list.push(_whitelist[i]);
        }
        whitelist[round].minted = false;
        emit AddWhitelist(uint32(round), uint32(whitelist[round].list.length));
    }

    function safeBatchMintToWhitelist(string memory uri, uint256 _index)
        public
        virtual
        onlyRole(MINTER_ROLE)
    {
        address[] memory list = getWhitelist(_index);

        for (uint256 i = 0; i < list.length; i++) {
            safeMint(list[i], uri);
        }

        whitelist[_index].minted = true;
    }

    function getWhitelist(uint256 _index)
        public
        view
        returns (address[] memory)
    {
        address[] memory list;
        list = whitelist[_index].list;
        return list;
    }
}
