// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721Token.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IERC721Burnable {
    function burn(uint256 tokenId) external;
}

contract AirDrop is ERC721Token, IERC721Receiver, ReentrancyGuard {
    address public quote = address(0);

    using Counters for Counters.Counter;
    using SafeMath for uint256;

    Counters.Counter[100] private _tokenIdCounter;

    bool public soulbound = false;
    uint256 public totalItems = 0;
    uint256 public totalSold = 0;
    uint256 public launch;
    uint256 public lockup;

    address public payment;
    address public treasury;
    uint256 public feeRate = 50; // Default 5%

    string[] public itemURIs;
    uint256[] public itemAmounts;
    uint256[] public itemSolds;
    //    uint256[] public itemPrices;
    bool private isRegistered = false;

    address[] public mandatory;
    bool public flagMandatory = false;
    bool public andOr;

    event SetLaunch(uint256);
    event SetLockup(uint256);
    event SetQuote(address);
    event SetConfig(address, address, uint256);
    event SetSoulbound(bool);

    modifier isNotRegistered() {
        require(isRegistered == false, "Items already registered");
        _;
    }

    /*
     * string name,
     * string symbol,
     * address _quote,
     * address _payment,
     * address _treasury,
     * bppl soulbound,
     * index 0 = uint256 _launch,
     * index 1 = uint256 _lockup,
     * index 2 = uint256 _feeRate
     */
    constructor(
        string memory name,
        string memory symbol,
        address _quote,
        address _payment,
        address _treasury,
        bool _soulbound,
        uint256[] memory configValues
    ) ERC721Token(name, symbol) {
        require(configValues.length == 3, "invalid config data length");

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        setLaunch(configValues[0]);
        setLockup(configValues[1]);
        setConfig(_payment, _treasury, configValues[2]);
        setQuote(_quote);
        setSoulbound(_soulbound);
    }

    function setConfig(
        address _payment,
        address _treasury,
        uint256 _feeRate
    ) public onlyOwner {
        require(_payment != address(0), "invalid payment address");
        require(_treasury != address(0), "invalid treasury address");
        payment = _payment;
        treasury = _treasury;
        feeRate = _feeRate;

        emit SetConfig(payment, treasury, feeRate);
    }

    function setSoulbound(bool _soulbound) public onlyOwner {
        soulbound = _soulbound;
        emit SetSoulbound(soulbound);
    }

    function setLaunch(uint256 _launch) public onlyOwner {
        launch = _launch;
        emit SetLaunch(launch);
    }

    function setLockup(uint256 _lockup) public onlyOwner {
        lockup = _lockup;
        emit SetLockup(lockup);
    }

    function setQuote(address _quote) public onlyOwner {
        quote = _quote;
        emit SetQuote(quote);
    }

    function setMandatory(address[] calldata _nfts, bool _andOr)
        public
        onlyOwner
    {
        if (_nfts.length > 0) {
            for (uint256 i = 0; i < _nfts.length; i++) {
                mandatory.push(_nfts[i]);
            }
            flagMandatory = true;
        }
        andOr = _andOr;
    }

    function safeMint(address to, string memory uri)
        public
        view
        override
        onlyRole(MINTER_ROLE)
        returns (uint256)
    {
        revert("Disabled");
    }

    function mintByTokenId(
        address to,
        uint256 tokenId,
        string memory uri
    ) internal override returns (uint256) {
        uint256 id = super.mintByTokenId(to, tokenId, uri);
        return id;
    }

    function safeBatchMint(address to, string[] memory uris)
        public
        view
        override
        onlyRole(MINTER_ROLE)
    {
        revert("Disabled");
    }

    // Post-Mint Items, mint when claim
    function registerItems(string[] memory uris, uint256[] memory amounts)
        public
        //        uint256[] memory prices
        onlyRole(MINTER_ROLE)
        isNotRegistered
    {
        require(uris.length == amounts.length, "Array length mismatch");

        itemAmounts = amounts;
        itemURIs = uris;
        //        itemPrices = prices;

        for (uint256 i = 0; i < uris.length; i++) {
            totalItems = totalItems.add(amounts[i]);
            _tokenIdCounter[i].increment();
            itemSolds.push(0);
        }
        isRegistered = true;
    }

    function claim() public {
        require(block.timestamp > launch, "Not yet launch time reached");
        require(totalItems > totalSold, "aridrop sold out");

        if (flagMandatory) {
            uint256 nPurchased = 0;
            for (uint256 i = 0; i < mandatory.length; i++) {
                uint256 balance = IERC721(mandatory[i]).balanceOf(msg.sender);
                if (andOr) {
                    require(balance > 0, "should buy all collections before");
                    nPurchased = nPurchased.add(1);
                } else {
                    if (balance > 0) {
                        nPurchased = nPurchased.add(1);
                        break;
                    }
                }
            }
            require(nPurchased > 0, "should buy all collections before");
        }

        uint256 _itemIx = 0;
        uint256 tokenId;
        for (uint256 i = 0; i < itemAmounts.length; i++) {
            if (itemSolds[i] >= itemAmounts[i]) {
                tokenId = tokenId.add(itemAmounts[i]);
            } else {
                _itemIx = i;
            }
        }

        tokenId = tokenId.add(_tokenIdCounter[_itemIx].current());
        mintByTokenId(msg.sender, tokenId, itemURIs[_itemIx]);
        _tokenIdCounter[_itemIx].increment();
        itemSolds[_itemIx] = itemSolds[_itemIx].add(1);
        totalSold = totalSold.add(1);
    }

    function buyItemCredit(
        uint256 _itemIx,
        uint256 amount,
        address to
    ) public {
        require(block.timestamp > launch, "Not yet launch time reached");
        require(totalItems > totalSold, "aridrop sold out");

        //        if (flagMandatory) {
        //            uint256 nPurchased = 0;
        //            for (uint256 i = 0; i < mandatory.length; i++) {
        //                uint256 balance = IERC721(mandatory[i]).balanceOf(msg.sender);
        //                if (andOr) {
        //                    require(balance > 0, "should buy all collections before");
        //                    nPurchased = nPurchased.add(1);
        //                } else {
        //                    if (balance > 0) {
        //                        nPurchased = nPurchased.add(1);
        //                        break;
        //                    }
        //                }
        //            }
        //            require(nPurchased > 0, "should buy all collections before");
        //        }

        //        uint256 _itemIx = 0;
        uint256 startId;
        for (uint256 i = 0; i < itemAmounts.length; i++) {
            if (itemSolds[i] >= itemAmounts[i]) {
                startId = startId.add(itemAmounts[i]);
            } else {
                _itemIx = i;
            }
        }

        for (uint256 i = 0; i < amount; i++) {
            uint256 tokenId = startId.add(_tokenIdCounter[_itemIx].current());
            mintByTokenId(to, tokenId, itemURIs[_itemIx]);
            _tokenIdCounter[_itemIx].increment();
            itemSolds[_itemIx] = itemSolds[_itemIx].add(1);
            totalSold = totalSold.add(1);
        }
    }

    //    function buyItemEth(uint256 _itemIx, uint256 _amount) public payable {
    //        require(quote == address(0), "Wrong quote token");
    //        require(block.timestamp > launch, "Not yet launch time reached");
    //        require(msg.value > 0, "value should be greater than zero");
    //        require(
    //            msg.value == _amount.mul(itemPrices[_itemIx]),
    //            "value and amount is not match"
    //        );
    //        require(itemAmounts[_itemIx] > itemSolds[_itemIx], "item sold out");
    //
    //        uint256 startId;
    //        for (uint256 i = 0; i < itemAmounts.length; i++) {
    //            if (_itemIx < i) {
    //                startId = startId.add(itemAmounts[i]);
    //            }
    //        }
    //
    //        for (uint256 i = 0; i < _amount; i++) {
    //            uint256 tokenId = startId.add(_tokenIdCounter[_itemIx].current());
    //            mintByTokenId(msg.sender, tokenId, itemURIs[_itemIx]);
    //            _tokenIdCounter[_itemIx].increment();
    //        }
    //
    //        settlement(_itemIx, _amount);
    //        itemSolds[_itemIx] = itemSolds[_itemIx].add(1);
    //    }
    //
    //    function buyItemQuote(
    //        uint256 _itemIx,
    //        uint256 _payment,
    //        uint256 _amount
    //    ) public payable {
    //        require(quote != address(0), "Wrong quote token");
    //        require(block.timestamp > launch, "Not yet launch time reached");
    //        require(_payment > 0, "value should be greater than zero");
    //        require(
    //            _payment == _amount.mul(itemPrices[_itemIx]),
    //            "value and amount is not match"
    //        );
    //
    //        uint256 balance = IERC20(quote).balanceOf(msg.sender);
    //        require(balance > _payment, "lack of quote token balance");
    //        require(itemAmounts[_itemIx] > itemSolds[_itemIx], "item sold out");
    //
    //        TransferHelper.safeTransferFrom(
    //            quote,
    //            msg.sender,
    //            address(this),
    //            _payment
    //        );
    //
    //        uint256 startId;
    //        for (uint256 i = 0; i < itemAmounts.length; i++) {
    //            if (_itemIx < i) {
    //                startId = startId.add(itemAmounts[i]);
    //            }
    //        }
    //
    //        for (uint256 i = 0; i < _amount; i++) {
    //            uint256 tokenId = startId.add(_tokenIdCounter[_itemIx].current());
    //            mintByTokenId(msg.sender, tokenId, itemURIs[_itemIx]);
    //            _tokenIdCounter[_itemIx].increment();
    //        }
    //
    //        settlement(_itemIx, _amount);
    //        itemSolds[_itemIx] = itemSolds[_itemIx].add(1);
    //    }
    //
    //    function settlement(uint256 index, uint256 amount) private {
    //        require(payment != address(0), "payment address is not set");
    //
    //        // 직접 판매인 경우에만 컬렉션에서 수수료 징수
    //        // Fee 5%
    //        uint256 revenue = amount.mul(itemPrices[index]);
    //        uint256 fee = revenue.mul(feeRate).div(1000);
    //        uint256 profit = revenue.sub(fee);
    //
    //        if (quote != address(0)) {
    //            // Talken Fee
    //            TransferHelper.safeTransferFrom(
    //                quote,
    //                address(this),
    //                treasury,
    //                fee
    //            );
    //            // Creator earnings
    //            TransferHelper.safeTransferFrom(
    //                quote,
    //                address(this),
    //                payment,
    //                profit
    //            );
    //        } else {
    //            // Talken Fee
    //            TransferHelper.safeTransferETH(treasury, fee);
    //            // Creator earnings
    //            TransferHelper.safeTransferETH(payment, profit);
    //        }
    //    }

    receive() external payable {}

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) public pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function getItemRemains() public view returns (uint256) {
        uint256 remains = 0;
        for (uint256 i = 0; i < itemAmounts.length; i++) {
            remains = remains.add(itemAmounts[i].sub(itemSolds[i]));
        }
        return remains;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId);

        if (soulbound == true) {
            if (
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
}
