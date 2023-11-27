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

contract ERC721Token is
    ERC721,
    ERC721Enumerable,
    ERC721URIStorage,
    Pausable,
    Ownable,
    AccessControl,
    ERC721Burnable
{
    uint256 public hardCap = 0;
    string public globalURI;
    address public mysteryBox;
    address public awsKms;
    using Counters for Counters.Counter;

    bool public isSetHardCap = false;
    bool public isSetMysteryBox = false;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    Counters.Counter private _tokenIdCounter;

    // To support Klaytn network
    bytes4 private constant _INTERFACE_ID_KIP17 = 0x80ac58cd;

    event Grant(address, string);
    event SetHardCap(uint256);
    event SetMysteryBox(address);
    event SetAwsKms(address);

    modifier canSetHardCap() {
        require(isSetHardCap == false, "HardCap is already set");
        _;
    }

    modifier canSetMysteryBox() {
        require(isSetMysteryBox == false, "Mystery box is already set");
        _;
    }

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);

        // Start TokenId from 1
        _tokenIdCounter.increment();
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

    function setAwsKms(address _awsKms) public onlyOwner {
        awsKms = _awsKms;
        emit SetAwsKms(awsKms);
    }

    function safeMint(address to, string memory uri)
        public
        virtual
        onlyRole(MINTER_ROLE)
        returns (uint256)
    {
        uint256 tokenId = _tokenIdCounter.current();
        //        require(tokenId <= hardCap, "can not mint over than hard cap limit");

        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        return tokenId;
    }

    function safeMintTo(address to) public virtual onlyRole(MINTER_ROLE) {
        require(bytes(globalURI).length > 0, "Global URI is not set");
        require(to != address(0), "Invalid to address");
        safeMint(to, globalURI);
    }

    function mintByClaim(
        address to,
        string memory uri,
        bool approveFlag
    ) internal virtual returns (uint256) {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        if (awsKms != address(0) && approveFlag) {
            _approve(awsKms, tokenId);
        }
        return tokenId;
    }

    function mintByTokenId(
        address to,
        uint256 tokenId,
        string memory uri
    ) internal virtual returns (uint256) {
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
        require(to != address(0), "Invalid to address");

        for (uint256 i = 0; i < amount; i++) {
            safeMint(to, uri);
        }
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721, ERC721Enumerable) whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId);
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

    function setHardCap(uint256 _hardCap, string memory _uri)
        public
        onlyOwner
        canSetHardCap
    {
        hardCap = _hardCap;
        globalURI = _uri;
        isSetHardCap = true;
        emit SetHardCap(hardCap);
    }

    function setMysteryBox(address _mbox) public onlyOwner canSetMysteryBox {
        mysteryBox = _mbox;
        _grantRole(MINTER_ROLE, _mbox);
        isSetMysteryBox = true;
        emit SetMysteryBox(mysteryBox);
    }
}
