// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "witnet-solidity-bridge/contracts/interfaces/IWitnetRandomness.sol";
import "./interfaces/IMysteryBox.sol";
import "./WhiteListNFT.sol";

interface IERC721Burnable {
    function burn(uint256 tokenId) external;
}

contract Subscription is Ownable, Pausable, IERC721Receiver, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct Config {
        address quote;
        uint256 rate;
        uint256 total;
        uint256 ratePrice;
        uint256 evenPrice;
        uint256 launch;
        uint256 startClaim;
        address payment;
        address treasury;
        uint256 shareRate;
        uint256 mboxRate;
        address mysterybox;
    }
    Config public config;

    uint256 public totalFund;
    uint256 public rateAmount;
    uint256 public evenAmount;

    address[] public whitelist;
    mapping(address => bool) private whitelistTypes;

    struct Holding {
        address nft;
        uint256 tokenId;
    }
    mapping(address => Holding[]) private holdings;
    bool public andor = false; // default = or operation

    uint32 public randomness;
    uint256 public latestRandomizingBlock;
    IWitnetRandomness public immutable witnet;
    uint256 private nonce = 0;

    uint256 public MaxBooking = 100000;
    struct Book {
        address user;
        uint256 staking;
        uint256 balance;
        uint256 rateMaxAlloc;
        uint256 evenMaxAlloc;
        uint256 rateAlloc;
        uint256 evenAlloc;
        uint256 totalAlloc;
        bool status;
        bool claimed;
    }

    bool public allocStatus = false;

    mapping(address => uint256) public depositList;
    using Counters for Counters.Counter;
    Counters.Counter private nDeposit;
    mapping(address => uint256) public depositIndex; // Book Index
    uint256 public totStakers = 0;

    Book[] public booking;
    uint256 private _inProcess = 0;
    uint256[] private randList;
    uint256 private _used = 0;

    event Staking(address, address, uint256);
    event UnStaking(address, uint256);
    event Claim(address, uint256, uint256, uint256);
    event SetWhiteList(address[], bool[], bool);
    event SetConfig(Config);
    event Refund(address, uint256, uint256);
    event RefundNFT(address, uint256);

    modifier initialized() {
        require(
            config.treasury != address(0) && config.payment != address(0),
            "Not yet mystery box initialized"
        );
        _;
    }

    modifier allocated() {
        require(allocStatus == true, "Not yet mystery box allocated");
        _;
    }

    modifier isNotAllocated() {
        require(allocStatus == false, "Mystery box is already allocated");
        _;
    }

    /**
     * index 0 = _ratePrice : 비례 배분 가격
     * index 1 = _evenPrice : 균등 배분 가격
     * index 2 = _amount : NFT 총수량
     * index 3 = _rate : 비례 배분 수량 비율
     * index 4 = _shareRate : 청약 Klaybay 수수료율
     * index 5 = _mboxRate : 미스터리박스 Klaybay 수수료율
     * index 6 = _launch : Staking 시작 시간
     * index 7 = _startClaim : Claim 시작 시간
     * _quote : Quote Token 주소
     * _payment : 게임사 지갑
     * _treasury : Klaybay 수수료 지갑
     * _whitelist : Whitelist NFT 목록
     * _types : Whitelist NFT 유형
     * _andor : Whitelist NFT 검증 방식
     * _mysterybox : 미스터리박스 컨트랙 주소
     * witnetRandomness : WitNet 컨트랙 주소
     **/

    constructor(
        // To avoid HH600 (Stack too deep) CompilerError
        uint256[] memory configValues,
        address _quote,
        address _payment,
        address _treasury,
        address _mysterybox,
        address[] memory _whitelist,
        bool[] memory _types,
        bool _andor,
        IWitnetRandomness _witnetRandomness
    ) {
        _setConfig(configValues, _quote, _payment, _treasury, _mysterybox);
        _setWhiteList(_whitelist, _types, _andor);

        require(
            address(_witnetRandomness) != address(0),
            "Wrong WitNET address"
        );
        witnet = _witnetRandomness;

        rateAmount = config.total.mul(config.rate).div(100); // 30 = 0.3 = 30%
        evenAmount = config.total.sub(rateAmount);

        // Exclude index 0
        booking.push(
            Book({
                user: address(this),
                staking: 0,
                balance: 0,
                rateMaxAlloc: 0,
                evenMaxAlloc: 0,
                rateAlloc: 0,
                evenAlloc: 0,
                totalAlloc: 0,
                status: true,
                claimed: false
            })
        );
        nDeposit.increment();
    }

    // Only for staking with Klay
    function stakingEth()
        public
        payable
        initialized
        isNotAllocated
        nonReentrant
    {
        require(
            nDeposit.current() < MaxBooking,
            "All books are filled already"
        );
        require(config.quote == address(0), "Wrong quote token");
        require(block.timestamp >= config.launch, "Starking is not started");

        if (depositList[msg.sender] == 0) {
            require(
                msg.value >= Math.max(config.ratePrice, config.evenPrice),
                "Under least staking amount"
            );
        }
        depositList[msg.sender] = depositList[msg.sender].add(msg.value);

        //        uint256 _index = _getIndexByAddress(msg.sender);
        uint256 _index = depositIndex[msg.sender];
        if (_index > 0) {
            booking[_index].staking = booking[_index].staking.add(msg.value);
            booking[_index].balance = booking[_index].balance.add(msg.value);
            booking[_index].rateMaxAlloc = booking[_index].staking.div(
                config.ratePrice
            );
        } else {
            depositIndex[msg.sender] = nDeposit.current();
            uint256 max = msg.value.div(config.ratePrice);
            booking.push(
                Book({
                    user: msg.sender,
                    staking: msg.value,
                    balance: msg.value,
                    rateMaxAlloc: max,
                    evenMaxAlloc: 0,
                    rateAlloc: 0,
                    evenAlloc: 0,
                    totalAlloc: 0,
                    status: false,
                    claimed: false
                })
            );
            nDeposit.increment();

            // Whitelist 컨트랙을 사용하는 경우
            if (whitelist.length > 0) {
                _stakingNFT(msg.sender);
            }
        }

        totalFund = totalFund.add(msg.value);
        totStakers++;

        emit Staking(msg.sender, config.quote, msg.value);
    }

    // Before this Approve on quote token is needed
    function stakingQuote(uint256 _payment)
        public
        initialized
        isNotAllocated
        nonReentrant
    {
        require(
            nDeposit.current() < MaxBooking,
            "All books are filled already"
        );
        require(config.quote != address(0), "Wrong quote token");
        require(block.timestamp >= config.launch, "Starking is not started");

        if (depositList[msg.sender] == 0) {
            require(
                _payment >= Math.max(config.ratePrice, config.evenPrice),
                "Under least staking amount"
            );
        }
        depositList[msg.sender] = depositList[msg.sender].add(_payment);

        //        uint256 _index = _getIndexByAddress(msg.sender);
        uint256 _index = depositIndex[msg.sender];
        if (_index > 0) {
            booking[_index].staking = booking[_index].staking.add(_payment);
            booking[_index].balance = booking[_index].balance.add(_payment);
            booking[_index].rateMaxAlloc = booking[_index].staking.div(
                config.ratePrice
            );
        } else {
            depositIndex[msg.sender] = nDeposit.current();
            uint256 max = _payment.div(config.ratePrice);
            booking.push(
                Book({
                    user: msg.sender,
                    staking: _payment,
                    balance: _payment,
                    rateMaxAlloc: max,
                    evenMaxAlloc: 0,
                    rateAlloc: 0,
                    evenAlloc: 0,
                    totalAlloc: 0,
                    status: false,
                    claimed: false
                })
            );
            nDeposit.increment();

            // Whitelist 컨트랙을 사용하는 경우
            if (whitelist.length > 0) {
                _stakingNFT(msg.sender);
            }
        }

        TransferHelper.safeTransferFrom(
            config.quote,
            msg.sender,
            address(this),
            _payment
        );

        totalFund = totalFund.add(_payment);
        totStakers++;

        emit Staking(msg.sender, config.quote, _payment);
    }

    function _stakingNFT(address user) private {
        uint256 own;
        uint256 nWhitelist = 0;
        for (uint256 i = 0; i < whitelist.length; i++) {
            own = IERC721(whitelist[i]).balanceOf(user);
            if (own > 0) {
                nWhitelist++;
                uint256 tokenId = IERC721Enumerable(whitelist[i])
                    .tokenOfOwnerByIndex(user, 0);
                holdings[user].push(
                    Holding({nft: whitelist[i], tokenId: tokenId})
                );
                if (andor == false) break;
            }
        }

        if (andor)
            require(
                nWhitelist == whitelist.length,
                "Lack of owned whitelist NFTs"
            );

        for (uint256 i = 0; i < holdings[user].length; i++) {
            IERC721(holdings[user][i].nft).safeTransferFrom(
                user,
                address(this),
                holdings[user][i].tokenId
            );
        }
    }

    function _refundNFT(address user, bool burn) private {
        uint256 nRefund = 0;

        for (uint256 i = 0; i < holdings[user].length; i++) {
            if (whitelistTypes[holdings[user][i].nft] == true && burn == true) {
                IERC721Burnable(holdings[user][i].nft).burn(
                    holdings[user][i].tokenId
                );
            } else {
                IERC721(holdings[user][i].nft).safeTransferFrom(
                    address(this),
                    user,
                    holdings[user][i].tokenId
                );
                nRefund++;
            }
        }

        emit RefundNFT(user, nRefund);
    }

    //    function allocation() public onlyOwner initialized {
    //        // Allocation by staking rates
    //        for (uint256 i = 1; i < booking.length; i++) {
    //            uint256 used = 0;
    //            uint256 num = rateAmount.mul(booking[i].staking).div(totalFund);
    //
    //            if (num >= booking[i].rateMaxAlloc) {
    //                booking[i].rateAlloc = booking[i].rateMaxAlloc;
    //                _used = _used.add(booking[i].rateMaxAlloc);
    //            } else if (num > 0 && num < booking[i].rateMaxAlloc) {
    //                booking[i].rateAlloc = num;
    //                _used = _used.add(num);
    //            }
    //
    //            booking[i].totalAlloc = booking[i].totalAlloc.add(
    //                booking[i].rateAlloc
    //            );
    //            used = booking[i].rateAlloc.mul(config.ratePrice);
    //            booking[i].balance = booking[i].balance.sub(used);
    //
    //            if (booking[i].balance < config.evenPrice) {
    //                booking[i].status = true;
    //            } else {
    //                _inProcess++;
    //            }
    //        }
    //
    //        // Hand over left NFTs to evenly allocation
    //        if (_used < rateAmount) {
    //            evenAmount = evenAmount.add(rateAmount).sub(_used);
    //        }
    //
    //        for (uint256 i = 1; i < booking.length; i++) {
    //            if (booking[i].status == false) {
    //                booking[i].evenMaxAlloc = booking[i].balance.div(
    //                    config.evenPrice
    //                );
    //            }
    //        }
    //
    //        // Even Allocation
    //        while (evenAmount > 0 && _inProcess > 0 && evenAmount >= _inProcess) {
    //            _evenlyDist();
    //        }
    //
    //        // Random Allocation on the left NFTs sill
    //        if (evenAmount > 0 && _inProcess > 0 && evenAmount < _inProcess) {
    //            _makeListForRand();
    //            _randomlyDist();
    //        }
    //
    //        allocStatus = true;
    //    }
    //
    //    function _evenlyDist() private {
    //        for (uint256 i = 1; i < booking.length; i++) {
    //            if (booking[i].status == false) {
    //                booking[i].evenAlloc = booking[i].evenAlloc.add(1);
    //                booking[i].totalAlloc = booking[i].totalAlloc.add(1);
    //                booking[i].balance = booking[i].balance.sub(config.evenPrice);
    //                if (booking[i].evenAlloc >= booking[i].evenMaxAlloc) {
    //                    booking[i].status = true;
    //                    _inProcess--;
    //                }
    //                evenAmount--;
    //            }
    //        }
    //    }
    //
    //    function _makeListForRand() private {
    //        for (uint256 i = 1; i < booking.length; i++) {
    //            if (booking[i].status == false) {
    //                randList.push(i);
    //            }
    //        }
    //    }
    //
    //    function _removeRandList(uint256 ix) private {
    //        //        for (uint256 i = ix; i < randList.length; i++) {
    //        //            for (uint256 j = i; j < randList.length - 1; j++) {
    //        //                randList[j] = randList[j + 1];
    //        //            }
    //        //        }
    //        if (ix < randList.length - 1) {
    //            for (uint256 i = ix; i < randList.length - 1; i++) {
    //                randList[i] = randList[i + 1];
    //            }
    //        }
    //        randList.pop();
    //    }
    //
    //    function _randomlyDist() private {
    //        while (evenAmount > 0 && _inProcess > 0) {
    //            _fetchRandomNumber(uint32(randList.length.sub(1)));
    //
    //            uint256 ix = randList[randomness];
    //
    //            booking[ix].evenAlloc = booking[ix].evenAlloc.add(1);
    //            booking[ix].totalAlloc = booking[ix].totalAlloc.add(1);
    //            booking[ix].balance = booking[ix].balance.sub(config.evenPrice);
    //            evenAmount = evenAmount.sub(1);
    //
    //            if (booking[ix].evenAlloc >= booking[ix].evenMaxAlloc) {
    //                booking[ix].status = true;
    //                _inProcess = _inProcess.sub(1);
    //            }
    //            _removeRandList(randomness);
    //        }
    //    }

    function unStaking(uint256 _amount) public isNotAllocated nonReentrant {
        require(_amount > 0, "Unstake more the zero");
        require(
            allocStatus == false,
            "Can cancel subscription when NFTs are not allocated"
        );

        //        uint256 _index = _getIndexByAddress(msg.sender);
        uint256 _index = depositIndex[msg.sender];
        //        require(
        //            booking[_index].staking.sub(_amount) >=
        //                Math.max(config.ratePrice, config.evenPrice),
        //            "Under least staking amount"
        //        );

        uint256 unStakeAmount = 0;

        if (_amount < booking[_index].staking) {
            booking[_index].staking = booking[_index].staking.sub(_amount);
            booking[_index].balance = booking[_index].balance.sub(_amount);
            booking[_index].rateMaxAlloc = booking[_index].staking.div(
                config.ratePrice
            );
            totalFund = totalFund.sub(_amount);
            depositList[msg.sender] = depositList[msg.sender].sub(_amount);

            unStakeAmount = _amount;
        } else {
            totalFund = totalFund.sub(booking[_index].staking);
            unStakeAmount = booking[_index].balance;

            // Remove related data
            depositList[msg.sender] = 0;

            // Remove from booking list
            depositIndex[msg.sender] = 0;
            //            for (uint256 i = _index; i < booking.length; i++) {
            //                for (uint256 j = i; j < booking.length - 1; j++) {
            //                    booking[j] = booking[j + 1];
            //                    depositIndex[booking[j].user] = j;
            //                }
            //            }

            // FIXME: 이렇게 처리는게 맞나? (loop 제거하고 booking에 flag 처리가 필요할 듯)
            for (uint256 i = _index; i < booking.length - 1; i++) {
                booking[i] = booking[i + 1];
                depositIndex[booking[i + 1].user] = i;
            }
            booking.pop();

            if (whitelist.length > 0) {
                // Not Burn one time Whitelist NFT
                _refundNFT(msg.sender, false);
            }

            totStakers--;
        }

        // Change unstaking fee
        _refund(msg.sender, unStakeAmount, true);

        emit UnStaking(msg.sender, unStakeAmount);
    }

    //    function _shuffle() private {
    //        for (uint256 i = 0; i < randList.length; i++) {
    //            //            uint256 n = i + uint256(keccak256(abi.encodePacked(block.timestamp))) % (items.length - i);
    //            //            uint256 n = i + uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender))) % (items.length - i);
    //            uint256 n = i +
    //                (uint256(
    //                    keccak256(
    //                        abi.encodePacked(
    //                            block.timestamp,
    //                            block.difficulty,
    //                            msg.sender
    //                        )
    //                    )
    //                ) % (randList.length - i));
    //            uint256 temp = randList[n];
    //            randList[n] = randList[i];
    //            randList[i] = temp;
    //        }
    //    }

    // 중요 : 반드시 포함되어야 하는 함수
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

    function _fetchRandomNumber(uint256 maximum) private {
        require(latestRandomizingBlock > 0, "Randomness is not initialized");
        randomness = witnet.random(
            uint32(maximum),
            nonce,
            latestRandomizingBlock
        );
        nonce++;
    }

    function _getIndexByAddress(address user) private view returns (uint256) {
        uint256 selected;
        for (uint256 i = 1; i < booking.length; i++) {
            if (booking[i].user == user) {
                selected = i;
                break;
            }
        }
        return selected;
    }

    function claim() external nonReentrant {
        require(depositList[msg.sender] > 0, "Only staked users can claim");
        require(
            block.timestamp >= config.startClaim,
            "Claim time is not yet reached"
        );

        //        uint256 ix = _getIndexByAddress(msg.sender);
        uint256 ix = depositIndex[msg.sender];
        require(booking[ix].claimed == false, "already claimed");

        // Calculate
        uint256 used = 0;
        uint256 num = rateAmount.mul(booking[ix].staking).div(totalFund);

        if (num >= booking[ix].rateMaxAlloc) {
            booking[ix].rateAlloc = booking[ix].rateMaxAlloc;
        } else if (num > 0 && num < booking[ix].rateMaxAlloc) {
            booking[ix].rateAlloc = num;
        }

        booking[ix].totalAlloc = booking[ix].totalAlloc.add(
            booking[ix].rateAlloc
        );
        used = booking[ix].rateAlloc.mul(config.ratePrice);
        booking[ix].balance = booking[ix].balance.sub(used);
        booking[ix].status = true;

        uint256 income = booking[ix].staking.sub(booking[ix].balance);
        uint256 totRate = config.shareRate.add(config.mboxRate);
        uint256 share = income.mul(totRate).div(1000);
        uint256 profit = income.sub(share);

        // Return Whitelist NFTs
        if (whitelist.length > 0) {
            // Burn one time Whitelist NFT
            _refundNFT(msg.sender, true);
        }

        // Return unused staking to depositor
        if (booking[ix].balance > 0) {
            // Not charging unStaking fee when claim
            _refund(booking[ix].user, booking[ix].balance, false);
        } else {
            emit Refund(booking[ix].user, 0, 0);
        }

        if (share > 0 || profit > 0) {
            if (config.quote != address(0)) {
                // Klaybay Fee
                //                TransferHelper.safeTransferFrom(
                //                    config.quote,
                //                    address(this),
                //                    config.treasury,
                //                    share
                //                );
                IERC20(config.quote).safeTransfer(config.treasury, share);
                // Game company earnings
                //                TransferHelper.safeTransferFrom(
                //                    config.quote,
                //                    address(this),
                //                    config.payment,
                //                    profit
                //                );
                IERC20(config.quote).safeTransfer(config.payment, profit);
            } else {
                // Klaybay Fee
                TransferHelper.safeTransferETH(config.treasury, share);
                // Game company earnings
                TransferHelper.safeTransferETH(config.payment, profit);
            }
        }

        if (booking[ix].totalAlloc > 0) {
            //        IMysteryBox(config.mysterybox).claimByStaking(
            //            msg.sender,
            //            booking[ix].totalAlloc
            //        );
            IMysteryBox(config.mysterybox).claimKeys(
                msg.sender,
                booking[ix].totalAlloc
            );
        }

        booking[ix].claimed = true;

        emit Claim(msg.sender, booking[ix].totalAlloc, share, profit);
    }

    function _refund(
        address to,
        uint256 _amount,
        bool flag
    ) private {
        require(_amount > 0, "No balance to refund");

        uint256 fee = 0;
        if (flag == true) {
            // Unstake 수수료 1%
            // TODO : 변경 가능해야 하는 지?
            fee = _amount.mul(10).div(1000);
        }

        if (address(config.quote) == address(0)) {
            TransferHelper.safeTransferETH(to, _amount.sub(fee));
            if (fee > 0) {
                TransferHelper.safeTransferETH(config.treasury, fee);
            }
        } else {
            //            TransferHelper.safeTransferFrom(
            //                address(config.quote),
            //                address(this),
            //                to,
            //                _amount.sub(fee)
            //            );
            IERC20(config.quote).safeTransfer(to, _amount.sub(fee));
            if (fee > 0) {
                //            TransferHelper.safeTransferFrom(
                //                address(config.quote),
                //                address(this),
                //                config.treasury,
                //                fee
                //            );
                IERC20(config.quote).safeTransfer(config.treasury, fee);
            }
        }

        emit Refund(to, _amount, fee);
    }

    function _setWhiteList(
        address[] memory _whitelist,
        bool[] memory _types,
        bool _andor
    ) private {
        require(_whitelist.length == _types.length, "Invalid array length");

        for (uint256 i = 0; i < _types.length; i++) {
            whitelist.push(_whitelist[i]);
            whitelistTypes[_whitelist[i]] = _types[i];
        }
        andor = _andor; // true = and operation

        emit SetWhiteList(whitelist, _types, andor);
    }

    /*
     * index 0 = _ratePrice : 비례 배분 가격
     * index 1 = _evenPrice : 균등 배분 가격
     * index 2 = _amount : NFT 총수량
     * index 3 = _rate : 비례 배분 수량 비율
     * index 4 = _shareRate : 청약 Klaybay 수수료율
     * index 5 = _mboxRate : 미스터리박스 Klaybay 수수료율
     * index 6 = _launch : Staking 시작 시간
     * index 7 = _startClaim : Claim 시작 시간
     */

    function _setConfig(
        uint256[] memory configValues,
        address _quote,
        address _payment,
        address _treasury,
        address _mysterybox
    ) private {
        require(configValues.length == 8, "missing config values");

        config.ratePrice = configValues[0];
        config.evenPrice = configValues[1];
        config.total = configValues[2];
        config.rate = configValues[3];
        config.shareRate = configValues[4];
        config.mboxRate = configValues[5];
        config.launch = configValues[6];
        config.startClaim = configValues[7]; // Launch + Duration + 24h

        config.quote = _quote;
        config.payment = _payment;
        config.treasury = _treasury;

        config.mysterybox = _mysterybox;

        emit SetConfig(config);
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) public pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function getAllocated() public view returns (bool) {
        return allocStatus;
    }

    function getLeastFund() public view returns (uint256) {
        uint256 realLeast = 0;
        uint256 leastFund = Math.max(config.ratePrice, config.evenPrice);
        if (rateAmount > 1) {
            realLeast = totalFund.div(rateAmount.sub(1));
        }

        uint256 result = 0;
        if (realLeast > leastFund) {
            result = realLeast;
        } else {
            result = leastFund;
        }
        return result;
    }

    function getParticipants() public view returns (uint256) {
        //        return booking.length.sub(1);
        return totStakers;
    }

    function getMyFund() public view returns (uint256) {
        return depositList[msg.sender];
    }

    function getBooking() public view returns (Book[] memory) {
        return booking;
    }

    function getMyWin() public view returns (uint256) {
        uint256 win = booking[depositIndex[msg.sender]].totalAlloc;
        return win;
    }

    function getClaimed() public view returns (bool) {
        return booking[depositIndex[msg.sender]].claimed;
    }
}
