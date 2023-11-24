// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721Token.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "witnet-solidity-bridge/contracts/interfaces/IWitnetRandomness.sol";

// import "./interfaces/ISubscription.sol";

interface IERC721Burnable {
    function burn(uint256 tokenId) external;
}

interface IMboxKey {
    function safeMintTo(address to) external;
}

contract MysteryBox is ERC721Token, IERC721Receiver, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public key;
    address public quote = address(0);
    uint256 public price;

    mapping(uint256 => string) tokenURIs;
    uint256[] public items;
    uint256 public totalItems = 0;
    uint256 public launch;
    uint256 public lockup;

    address public payment;
    address public treasury;
    uint256 public feeRate = 50; // Default 5%

    using SafeMath for uint256;
    uint32 public randomness;
    uint256 public latestRandomizingBlock;
    IWitnetRandomness public immutable witnet;
    uint256 private nonce = 0;

    string[] public itemURIs;
    uint256[] public itemAmounts;
    bool private isRegistered = false;

    address[] public mandatory;
    bool public flagMandatory = false;
    bool public andOr;
    bool public isSaleStarted = false;

    //    struct Subscription {
    //        address contractAddr;
    //        uint256 contractType; // 1 = 균등, 2 = 비례, 3 = LBP
    //        uint256 amount;
    //        uint256 start;
    //        uint256 end;
    //        uint256 count;
    //    }

    //    mapping(uint256 => Subscription) public subInfos;
    //    uint256 private nSubscriptions = 0;
    //    mapping(address => uint256) public subAddrs;
    uint256 private _curCount = 0;

    event SetMboxKey(address, uint256);
    //    event SetSubscription(address);
    event SetLaunch(uint256);
    event SetLockup(uint256);
    event SetQuote(address);
    event SetConfig(address, address, uint256);

    // TODO: Need to add more events to monitoring

    //    modifier isAllocated() {
    //        bool allocStatus = ISubscription(msg.sender).getAllocated();
    //        require(allocStatus == true, "Not subscription allocated yet");
    //        _;
    //    }

    modifier isNotRegistered() {
        require(isRegistered == false, "Items already registered");
        _;
    }

    modifier canSetMandatory() {
        require(
            flagMandatory == false && isSaleStarted == false,
            "flagMandatory already set"
        );
        _;
    }

    //    modifier onlySubscription() {
    //        require(nSubscriptions > 0, "No subscription contracts set");
    //        require(
    //            subInfos[subAddrs[msg.sender]].contractAddr == msg.sender,
    //            "Only subscription contract can call claimKeys"
    //        );
    //        _;
    //    }

    /*
     * string name,
     * string symbol,
     * string _key,
     * address _quote,
     * address _payment,
     * address _treasury,
     * index 0 = uint256 _launch,
     * index 1 = uint256 _lockup,
     * index 2 = uint256 _price,
     * index 3 = uint256 _feeRate,
     * IWitnetRandomness _witnetRandomness // WitNet contract address
     */
    constructor(
        string memory name,
        string memory symbol,
        address _key,
        address _quote,
        address _payment,
        address _treasury,
        uint256[] memory configValues,
        IWitnetRandomness _witnetRandomness
    ) ERC721Token(name, symbol) {
        require(configValues.length == 4, "invalid config data length");

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _setLaunch(configValues[0]);
        _setLockup(configValues[1]);
        _setMboxKey(_key, configValues[2]);
        _setConfig(_payment, _treasury, configValues[3]);
        _setQuote(_quote);
        require(
            address(_witnetRandomness) != address(0),
            "Wrong WitNET address"
        );
        witnet = _witnetRandomness;
    }

    function _setMboxKey(address _key, uint256 _price) private {
        require(_key != address(0), "Wrong MysteryBox contract address");
        key = _key;
        price = _price;
        emit SetMboxKey(key, price);
    }

    function _setConfig(
        address _payment,
        address _treasury,
        uint256 _feeRate
    ) private {
        // In case of null subscription contract handle clearing...
        require(_payment != address(0), "invalid payment address");
        require(_treasury != address(0), "invalid treasury address");
        payment = _payment;
        treasury = _treasury;
        feeRate = _feeRate;

        emit SetConfig(payment, treasury, feeRate);
    }

    //    function setSubscription(
    //        address _subscription,
    //        uint256 _type,
    //        uint256 _amount
    //    ) public onlyOwner {
    //        require(
    //            _subscription != address(0),
    //            "Wrong Subscription contract address"
    //        );
    //
    //        subAddrs[_subscription] = nSubscriptions;
    //        uint256 endCount = _curCount.add(_amount).sub(1);
    //        subInfos[nSubscriptions] = Subscription({
    //            contractAddr: _subscription,
    //            contractType: _type,
    //            amount: _amount,
    //            start: _curCount,
    //            end: endCount,
    //            count: 0
    //        });
    //        nSubscriptions++;
    //        _curCount = _curCount.add(_amount);
    //
    //        addMinter(_subscription);
    //
    //        emit SetSubscription(_subscription);
    //    }

    function _setLaunch(uint256 _launch) private {
        if (_launch == 0) {
            launch = block.timestamp;
        } else {
            launch = _launch;
        }
        emit SetLaunch(launch);
    }

    function _setLockup(uint256 _lockup) private {
        if (_lockup == 0) {
            lockup = block.timestamp;
        } else {
            lockup = _lockup;
        }
        lockup = _lockup;
        emit SetLockup(lockup);
    }

    function _setQuote(address _quote) private {
        quote = _quote;
        emit SetQuote(quote);
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

    function mintByClaim(
        address to,
        string memory uri,
        bool approveFlag
    ) internal override returns (uint256) {
        uint256 tokenId = super.mintByClaim(to, uri, approveFlag);
        return tokenId;
    }

    function safeBatchMint(address to, string[] memory uris)
        public
        view
        override
        onlyRole(MINTER_ROLE)
    {
        revert("Disabled");
    }

    // function makeItems(string[] memory uris) public onlyRole(MINTER_ROLE) {
    //     for (uint256 i = 0; i < uris.length; i++) {
    //         // The contract owner should has all items pre-minted to transfer it to claimers.
    //         uint256 tokenId = super.safeMint(Owner(), uris[i]);
    //         items.push(tokenId);
    //     }
    // }

    // Pre-Mint Items
    // To save GAS
    //    function makeItems(string[] memory uris, uint256[] memory amounts)
    //        public
    //        onlyRole(MINTER_ROLE)
    //    {
    //        require(uris.length == amounts.length, "Array length mismatch");
    //
    //        for (uint256 i = 0; i < uris.length; i++) {
    //            for (uint256 j = 0; j < amounts[i]; j++) {
    //                // The contract owner should has all items pre-minted to transfer it to claimers.
    //                uint256 tokenId = super.safeMint(owner(), uris[i]);
    //                items.push(tokenId);
    //            }
    //        }
    //    }

    // Post-Mint Items, mint when claim
    function registerItems(string[] memory uris, uint256[] memory amounts)
        public
        onlyRole(MINTER_ROLE)
        isNotRegistered
    {
        require(uris.length == amounts.length, "Array length mismatch");

        itemAmounts = amounts;
        itemURIs = uris;

        //        uint256 calldata tokenId = 0;
        //        for (uint256 i = 0; i < uris.length; i++) {
        //            for (uint256 j = 0; j < amounts[i]; j++) {
        //                //                tokenURIs[tokenId] = uris[i];
        //                items.push(tokenId);
        //                tokenId++;
        //
        //                //                totalItems++;
        //            }
        //        }

        for (uint256 i = 0; i < uris.length; i++) {
            totalItems = totalItems.add(amounts[i]);
        }
        isRegistered = true;
    }

    // Return key NFTs and receive unboxed items randomly
    // Payable for WitNet RAndomness Oracle
    function claim(address to, uint256 amount)
        public
        whenNotPaused
        nonReentrant
    {
        require(key != address(0), "key contract not set");
        require(to != address(0), "Wrong claim address");
        require(block.timestamp > lockup, "Not yet reveal time reached");

        uint256 balance = IERC721(key).balanceOf(msg.sender);
        require(
            balance > 0,
            "Only owners of MysteryBox can claim unboxed item(s)"
        );
        require(amount <= balance && amount > 0, "invalid claim amount");

        for (uint256 i = 0; i < amount; i++) {
            uint256 tokenId = IERC721Enumerable(key).tokenOfOwnerByIndex(
                msg.sender,
                0
            );

            // TODO : 어떤 걸 선택할까 ?
            //            IERC721Burnable(key).burn(tokenIds[i]); // Send to address(0)
            IERC721(key).safeTransferFrom( // Send to burn address
                msg.sender,
                0x000000000000000000000000000000000000dEaD,
                tokenId
            );

            _fetchRandomNumber(uint32(totalItems));

            mintByClaim(to, getTokenURI(randomness), false);
        }
    }

    // Claim by Talken Backend
    function buyItemCredit(
        uint256 index,
        uint256 amount,
        address to
    ) public whenNotPaused nonReentrant onlyRole(MINTER_ROLE) {
        require(key != address(0), "key contract not set");
        require(to != address(0), "Wrong claim address");
        require(block.timestamp > lockup, "Not yet reveal time reached");

        uint256 balance = IERC721(key).balanceOf(msg.sender);
        require(
            balance > 0,
            "Only owners of MysteryBox can claim unboxed item(s)"
        );
        require(amount <= balance && amount > 0, "invalid claim amount");

        for (uint256 i = 0; i < amount; i++) {
            uint256 tokenId = IERC721Enumerable(key).tokenOfOwnerByIndex(
                msg.sender,
                0
            );

            // TODO : 어떤 걸 선택할까 ?
            //            IERC721Burnable(key).burn(tokenIds[i]); // Send to address(0)
            IERC721(key).safeTransferFrom( // Send to burn address
                msg.sender,
                0x000000000000000000000000000000000000dEaD,
                tokenId
            );

            _fetchRandomNumber(uint32(totalItems));

            mintByClaim(to, getTokenURI(randomness), true);
        }
    }

    //    function claimKeys(address to, uint256 _amount)
    //        public
    //        whenNotPaused
    //        onlySubscription
    //        //        isAllocated
    //        nonReentrant
    //    {
    //        require(key != address(0), "key contract not set");
    //        require(to != address(0), "Wrong claim address");
    //        require(_amount > 0, "invalid tokenIds for claim");
    //        //        require(
    //        //            block.timestamp > launch.add(lockup),
    //        //            "Not yet reveal time reached"
    //        //        );
    //
    //        uint256 ix = subAddrs[msg.sender];
    //        uint256 tokenId = 0;
    //        for (uint256 i = 0; i < _amount; i++) {
    //            tokenId = subInfos[ix].start.add(subInfos[ix].count);
    //            require(tokenId <= subInfos[ix].end, "claim token Id overflow");
    //            //            IERC721(key).safeTransferFrom(address(this), to, tokenId);
    //            subInfos[ix].count++;
    //            IMboxKey(key).safeMintTo(to);
    //        }
    //    }

    // Caution : It's needed for Witnet
    receive() external payable {}

    function estimateRandomizeFee(uint256 gasPrice)
        external
        view
        returns (uint256)
    {
        uint256 fee = witnet.estimateRandomizeFee(gasPrice);
        return (fee);
    }

    //    function requestRandomNumber() external payable {
    //        latestRandomizingBlock = block.number;
    //        uint256 _usedFunds = witnet.randomize{value: msg.value}();
    //        if (_usedFunds < msg.value) {
    //            payable(msg.sender).transfer(msg.value - _usedFunds);
    //        }
    //    }
    function requestRandomNumber() external payable nonReentrant {
        latestRandomizingBlock = block.number;
        uint256 _usedFunds = witnet.randomize{value: msg.value}();
        if (_usedFunds < msg.value) {
            uint256 _amount = msg.value - _usedFunds;
            (bool success, ) = msg.sender.call{value: _amount}("");
            require(success, "Failed to payback for randomization fee");
        }
    }

    function _fetchRandomNumber(uint32 max) private {
        require(latestRandomizingBlock > 0, "Randomness is not initialized");
        randomness = witnet.random(max, nonce, latestRandomizingBlock);
        nonce++;
    }

    // Extract minted Token ID and shorten items.length
    //    function _deleteItemAfterMint(uint256 target) private {
    //        for (uint256 i = target; i < items.length; i++) {
    //            for (uint256 j = i; j < items.length - 1; j++) {
    //                items[j] = items[j + 1];
    //            }
    //        }
    //        items.pop();
    //    }

    function buyKeyEth(uint256 _amount) public payable {
        require(quote == address(0), "Wrong quote token");
        require(block.timestamp > launch, "Not yet launch time reached");
        require(msg.value > 0, "value should be greater than zero");
        require(
            msg.value == _amount.mul(price),
            "value and amount is not match"
        );
        require(
            //            key != address(0) && nSubscriptions == 0,
            key != address(0),
            "key contract is not set"
        );

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

        for (uint256 i = 0; i < _amount; i++) {
            IMboxKey(key).safeMintTo(msg.sender);
        }

        if (!isSaleStarted) isSaleStarted = true;
        settlement(_amount);
    }

    function buyKeyQuote(uint256 _payment, uint256 _amount) public {
        require(quote != address(0), "Wrong quote token");
        require(block.timestamp > launch, "Not yet launch time reached");
        require(_payment > 0, "value should be greater than zero");
        require(
            _payment == _amount.mul(price),
            "value and amount is not match"
        );
        uint256 balance = IERC20(quote).balanceOf(msg.sender);
        require(balance > _payment, "lack of quote token balance");

        if (flagMandatory) {
            uint256 nPurchased = 0;
            for (uint256 i = 0; i < mandatory.length; i++) {
                uint256 value = IERC721(mandatory[i]).balanceOf(msg.sender);
                if (andOr) {
                    require(value > 0, "should buy all collections before");
                    nPurchased = nPurchased.add(1);
                } else {
                    if (value > 0) {
                        nPurchased = nPurchased.add(1);
                        break;
                    }
                }
            }
            require(nPurchased > 0, "should buy all collections before");
        }

        //        TransferHelper.safeTransferFrom(
        //            quote,
        //            msg.sender,
        //            address(this),
        //            _payment
        //        );
        IERC20(quote).safeTransferFrom(msg.sender, address(this), _payment);

        for (uint256 i = 0; i < _amount; i++) {
            IMboxKey(key).safeMintTo(msg.sender);
        }

        if (!isSaleStarted) isSaleStarted = true;
        settlement(_amount);
    }

    // Buy NFT with Credits or in app payment...
    function buyKeyCredit(uint256 _amount, address to)
        public
        onlyRole(MINTER_ROLE)
    {
        require(block.timestamp > launch, "Not yet launch time reached");

        if (flagMandatory) {
            uint256 nPurchased = 0;
            for (uint256 i = 0; i < mandatory.length; i++) {
                uint256 value = IERC721(mandatory[i]).balanceOf(msg.sender);
                if (andOr) {
                    require(value > 0, "should buy all collections before");
                    nPurchased = nPurchased.add(1);
                } else {
                    if (value > 0) {
                        nPurchased = nPurchased.add(1);
                        break;
                    }
                }
            }
            require(nPurchased > 0, "should buy all collections before");
        }

        for (uint256 i = 0; i < _amount; i++) {
            IMboxKey(key).safeMintTo(to);
        }

        if (!isSaleStarted) isSaleStarted = true;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) public pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function settlement(uint256 amount) private {
        require(key != address(0), "key contract is not set");
        //        require(nSubscriptions == 0, "mysterybox invalid method call");
        require(payment != address(0), "payment address is not set");

        // 직접 판매인 경우에만 미스터리박스에서 수수료 징수
        // Fee 5%
        uint256 revenue = amount.mul(price);
        uint256 fee = revenue.mul(feeRate).div(1000);
        uint256 profit = revenue.sub(fee);

        if (quote != address(0)) {
            // Klaybay Fee
            //            TransferHelper.safeTransferFrom(
            //                quote,
            //                address(this),
            //                treasury,
            //                fee
            //            );
            IERC20(quote).safeTransfer(treasury, fee);
            // Game company earnings
            //            TransferHelper.safeTransferFrom(
            //                quote,
            //                address(this),
            //                payment,
            //                profit
            //            );
            IERC20(quote).safeTransfer(payment, profit);
        } else {
            // Klaybay Fee
            TransferHelper.safeTransferETH(treasury, fee);
            // Game company earnings
            TransferHelper.safeTransferETH(payment, profit);
        }
    }

    // return key token id range of a subscription contract
    //    function getSubInfos(address _subAddr)
    //        public
    //        view
    //        returns (
    //            address,
    //            uint256,
    //            uint256
    //        )
    //    {
    //        Subscription memory info = subInfos[subAddrs[_subAddr]];
    //        return (key, info.start, info.end);
    //    }

    function getTokenURI(uint256 tokenId) private returns (string memory) {
        uint256 ix;
        uint256 sum = 0;
        for (uint256 i = 0; i < itemURIs.length; i++) {
            sum = sum.add(itemAmounts[i]);
            if (tokenId < sum) {
                ix = i;
                break;
            }
        }
        totalItems = totalItems.sub(1);
        itemAmounts[ix] = itemAmounts[ix].sub(1);
        return (itemURIs[ix]);
    }

    //    function getItemAmounts() public view returns (uint256[] memory) {
    //        uint256[] memory amounts = itemAmounts;
    //        return amounts;
    //    }

    function getItemRemains() public view returns (uint256) {
        uint256 remains = 0;
        for (uint256 i = 0; i < itemAmounts.length; i++) {
            remains = remains.add(itemAmounts[i]);
        }
        return remains;
    }

    function setMandatory(address[] calldata _nfts, bool _andOr)
        public
        onlyOwner
        canSetMandatory
    {
        if (_nfts.length > 0) {
            for (uint256 i = 0; i < _nfts.length; i++) {
                mandatory.push(_nfts[i]);
            }
            flagMandatory = true;
        }
        andOr = _andOr;
    }
}
