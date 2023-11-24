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
import "@openzeppelin/contracts/utils/Counters.sol";
import "witnet-solidity-bridge/contracts/interfaces/IWitnetRandomness.sol";
import "./interfaces/IMysteryBox.sol";
import "./WhiteListNFT.sol";

interface IERC721Burnable {
    function burn(uint256 tokenId) external;
}

contract EvenAllocation is Ownable, Pausable, IERC721Receiver, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeMath for uint32;
    using SafeERC20 for IERC20;

    struct Config {
        address quote;
        uint256 rate;
        uint256 total;
        uint256 price;
        uint256 launch;
        uint256 startClaim;
        address payment;
        address treasury;
        uint256 shareRate;
        uint256 mboxRate;
        address mysterybox;
        uint256 maxTicket;
        uint256 perTicket;
    }
    Config public config;

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

    bool public allocStatus = false;

    uint256 public MaxBooking = 100000;
    struct Book {
        address user;
        uint256 nTickets;
        uint256 deposit;
        uint256 allocated;
        bool status;
        bool claimed;
    }
    Book[] public booking;

    mapping(address => uint256) public depositList; // Deposit Fund
    using Counters for Counters.Counter;
    Counters.Counter private nDeposit;
    mapping(address => uint256) public depositIndex; // Book Index
    uint256[] public ticketData;

    uint256 totalItems;
    uint256 public available;
    uint256 private ticketSold = 0;
    uint256 private remainTickets = 0;
    uint256[] private randList;

    event BuyTicket(address, address, uint256, uint256, uint256);
    event Refund(address, uint256, uint256);
    event Claim(address, uint256, uint256, uint256);
    event SetWhiteList(address[], bool[], bool);
    event SetConfig(Config);
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
     * index 0 = _price : 가격
     * index 1 = _amount : NFT 총수량
     * index 2 = _shareRate : 청약 Klaybay 수수료율
     * index 3 = _mboxRate : 미스터리박스 Klaybay 수수료율
     * index 4 = _launchg : Buy 가능 시간
     * index 5 = _startClaim : Claim 가능 시간
     * index 6 = _maxTicket : 지갑 당 최대 티켓
     * index 7 = _perTicket : 티켓 당 NFT 수량
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
        setWhiteList(_whitelist, _types, _andor);
        totalItems = config.total.div(config.perTicket);
        available = totalItems;

        require(
            address(_witnetRandomness) != address(0),
            "Wrong WitNET address"
        );
        witnet = _witnetRandomness;

        // Skip index 0
        booking.push(
            Book({
                user: address(this),
                nTickets: 0,
                deposit: 0,
                allocated: 0,
                status: true,
                claimed: false
            })
        );
        nDeposit.increment();
    }

    // Only for staking with Klay
    function buyTicketEth(uint256 _nTickets)
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
        require(
            block.timestamp >= config.launch,
            "Ticket sales is not started"
        );
        require(
            _nTickets > 0,
            "Number of tickets for purchasing should be greater than zero"
        );
        require(msg.value > 0, "Payment should be greater than zero");

        if (depositList[msg.sender] == 0) {
            //            require(msg.value >= config.price, "Under least staking amount");
            require(
                msg.value <= config.price.mul(config.maxTicket),
                "Can't buy more than maximum per wallet"
            );
            require(
                config.price.mul(_nTickets) == msg.value,
                "Wrong number of tickets to purchase"
            );
        } else {
            revert("only once can buy tickets");
        }

        depositList[msg.sender] = depositList[msg.sender].add(msg.value);

        // Insert only new depositors into booking
        if (depositIndex[msg.sender] == 0) {
            depositIndex[msg.sender] = nDeposit.current();
            booking.push(
                Book({
                    user: msg.sender,
                    nTickets: _nTickets,
                    deposit: msg.value,
                    allocated: 0,
                    status: false,
                    claimed: false
                })
            );
        } else {
            uint256 index = depositIndex[msg.sender];
            // Check one more
            if (booking[index].user == msg.sender) {
                booking[index].nTickets = booking[index].nTickets + _nTickets;
                booking[index].deposit = depositList[msg.sender];
            } else {
                revert("Booking list mismatch");
            }
        }

        for (uint256 i = 0; i < _nTickets; i++) {
            ticketData.push(nDeposit.current());
        }
        ticketSold = ticketSold.add(_nTickets);
        remainTickets = ticketSold;
        nDeposit.increment();

        // Whitelist 컨트랙을 사용하는 경우
        if (whitelist.length > 0) {
            _stakingNFT(msg.sender);
        }

        emit BuyTicket(
            msg.sender,
            config.quote,
            msg.value,
            _nTickets,
            ticketSold
        );
    }

    // Before this Approve on quote token is needed
    function buyTicketQuote(uint256 _payment, uint256 _nTickets)
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
        require(
            block.timestamp >= config.launch,
            "Ticket sales is not started"
        );
        require(
            _nTickets > 0,
            "Number of tickets for purchasing should be greater than zero"
        );
        require(_payment > 0, "Payment should be greater than zero");

        if (depositList[msg.sender] == 0) {
            //            require(_payment >= config.price, "Under least staking amount");
            require(
                _payment <= config.price.mul(config.maxTicket),
                "Can't buy more than maximum per wallet"
            );
            require(
                config.price.mul(_nTickets) == _payment,
                "Wrong number of tickets to purchase"
            );
        }

        depositList[msg.sender] = depositList[msg.sender].add(_payment);

        // Insert only new depositors into booking
        if (depositIndex[msg.sender] == 0) {
            depositIndex[msg.sender] = nDeposit.current();
            booking.push(
                Book({
                    user: msg.sender,
                    nTickets: _nTickets,
                    deposit: _payment,
                    allocated: 0,
                    status: false,
                    claimed: false
                })
            );
        } else {
            uint256 index = depositIndex[msg.sender];
            // Check one more
            if (booking[index].user == msg.sender) {
                booking[index].nTickets = booking[index].nTickets + _nTickets;
                booking[index].deposit = depositList[msg.sender];
            } else {
                revert("Booking list mismatch");
            }
        }

        for (uint256 i = 0; i < _nTickets; i++) {
            ticketData.push(nDeposit.current());
        }
        ticketSold = ticketSold.add(_nTickets);
        remainTickets = ticketSold;
        nDeposit.increment();

        // Whitelist 컨트랙을 사용하는 경우
        if (whitelist.length > 0) {
            _stakingNFT(msg.sender);
        }

        TransferHelper.safeTransferFrom(
            config.quote,
            msg.sender,
            address(this),
            _payment
        );

        emit BuyTicket(
            msg.sender,
            config.quote,
            _payment,
            _nTickets,
            ticketSold
        );
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
    //        // Allocation evenly by Randomness
    //        uint256 totTickets = config.total.div(config.perTicket);
    //        available = totTickets;
    //
    //        uint256 _inProcess = booking.length.sub(1); // exclude index 0
    //        while (available > 0 && available >= _inProcess && _inProcess > 0) {
    //            for (uint256 i = 1; i < booking.length; i++) {
    //                if (booking[i].status == false) {
    //                    booking[i].allocated = booking[i].allocated.add(1);
    //                    available = available.sub(1);
    //                    if (
    //                        booking[i].allocated >= booking[i].nTickets ||
    //                        booking[i].allocated >= config.maxTicket
    //                    ) {
    //                        booking[i].status = true;
    //                        _inProcess--;
    //                    }
    //                }
    //            }
    //        }
    //
    //        _makeListForRand();
    //        _randomlyDist();
    //
    //        allocStatus = true;
    //    }
    //
    //    function _randomlyDist() private {
    //        while (available > 0 && randList.length > 0) {
    //            _fetchRandomNumber(randList.length);
    //
    //            uint256 ix = randList[randomness];
    //
    //            if (booking[ix].status == false) {
    //                booking[ix].allocated = booking[ix].allocated.add(1);
    //                available = available.sub(1);
    //                if (
    //                    booking[ix].allocated >= config.maxTicket ||
    //                    booking[ix].allocated >= config.maxTicket
    //                ) {
    //                    booking[ix].status = true;
    //                }
    //                _removeRandList(randomness);
    //            } else {
    //                _removeRandList(randomness);
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

    //    function _getIndexByAddress(address user) private view returns (uint256) {
    //        uint256 selected;
    //        for (uint256 i = 1; i < booking.length; i++) {
    //            if (booking[i].user == user) {
    //                selected = i;
    //                break;
    //            }
    //        }
    //        return selected;
    //    }

    function claim() external nonReentrant {
        require(
            depositList[msg.sender] > 0,
            "Only users who bought tickets can claim"
        );
        require(
            block.timestamp >= config.startClaim,
            "Claim time is not yet reached"
        );
        //        require(available > 0, "all items were distributed");

        //        uint256 ix = _getIndexByAddress(msg.sender);
        uint256 ix = depositIndex[msg.sender];
        require(booking[ix].claimed == false, "already claimed");

        // Calculate allocated count
        if (ticketSold < totalItems) {
            booking[ix].allocated = booking[ix].nTickets;
            available = available.sub(booking[ix].nTickets);
        } else {
            //            //            _fetchRandomNumber(ticketData.length);
            //            //            if (ticketData[randomness] == ix && available > 0) {
            //            //                booking[ix].allocated = 1;
            //            //                available = available.sub(1);
            //            //            }
            //            if (available > 0) {
            //                _fetchRandomNumber(ticketData.length);
            //
            //                if (booking[ticketData[randomness]].allocated == 0) {
            //                    booking[ticketData[randomness]].allocated = 1;
            //                    available = available.sub(1);
            //                }
            //            }
            if (available > 0) {
                for (uint256 i = 0; i < booking[ix].nTickets; i++) {
                    _fetchRandomNumber(remainTickets);
                    if (randomness < available) {
                        booking[ix].allocated++;
                        available--;
                    }
                    remainTickets--;
                }
            }
        }

        uint256 income = booking[ix].allocated.mul(config.price);
        uint256 totRate = config.shareRate.add(config.mboxRate);
        uint256 share = income.mul(totRate).div(1000);
        uint256 profit = income.sub(share);

        // Return Whitelist NFTs
        if (whitelist.length > 0) {
            // Burn one time Whitelist NFT
            _refundNFT(msg.sender, true);
        }

        // Return unused staking to depositor
        if (booking[ix].deposit > income) {
            // Not charging unStaking fee when claim
            _refund(booking[ix].user, booking[ix].deposit.sub(income), false);
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

        if (booking[ix].allocated > 0) {
            //        IMysteryBox(config.mysterybox).claimByStaking(
            //            msg.sender,
            //            booking[ix].allocated.mul(config.perTicket)
            //        );
            IMysteryBox(config.mysterybox).claimKeys(
                msg.sender,
                booking[ix].allocated.mul(config.perTicket)
            );
        }

        booking[ix].claimed = true;

        emit Claim(msg.sender, booking[ix].allocated, share, profit);
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
            TransferHelper.safeTransferETH(config.treasury, fee);
        } else {
            TransferHelper.safeTransferFrom(
                address(config.quote),
                address(this),
                to,
                _amount.sub(fee)
            );
            TransferHelper.safeTransferFrom(
                address(config.quote),
                address(this),
                config.treasury,
                fee
            );
        }

        emit Refund(to, _amount, fee);
    }

    function setWhiteList(
        address[] memory _whitelist,
        bool[] memory _types,
        bool _andor
    ) public onlyOwner {
        require(_whitelist.length == _types.length, "Invalid array length");

        for (uint256 i = 0; i < _types.length; i++) {
            whitelist.push(_whitelist[i]);
            whitelistTypes[_whitelist[i]] = _types[i];
        }
        andor = _andor; // true = and operation

        emit SetWhiteList(whitelist, _types, andor);
    }

    function _setConfig(
        uint256[] memory configValues,
        address _quote,
        address _payment,
        address _treasury,
        address _mysterybox
    ) private {
        require(configValues.length == 8, "missing config values");

        /*
         * index 0 = _price : 가격
         * index 1 = _amount : NFT 총수량
         * index 2 = _shareRate : 청약 Klaybay 수수료율
         * index 3 = _mboxRate : 미스터리박스 Klaybay 수수료율
         * index 4 = _launch : Buy 가능 시간
         * index 5 = _startClaim : Claim 가능 시간
         * index 6 = _maxTicket : 지갑 당 최대 티켓
         * index 7 = _perTicket : 티켓 당 NFT 수량
         */

        config.price = configValues[0];
        config.total = configValues[1];
        config.shareRate = configValues[2];
        config.mboxRate = configValues[3];
        config.launch = configValues[4];
        config.startClaim = configValues[5];
        config.maxTicket = configValues[6];
        require(
            config.maxTicket > 0 && config.maxTicket <= 10,
            "Invalid max. tickets per wallet"
        );
        config.perTicket = configValues[7];
        require(
            config.perTicket > 0,
            "Invalid number of NFTs per ticket at least 1"
        );

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

    function getMyTickets() public view returns (uint256) {
        uint256 myTickets = booking[depositIndex[msg.sender]].nTickets;
        return myTickets;
    }

    function getMyWin() public view returns (uint256) {
        uint256 win = booking[depositIndex[msg.sender]].allocated;
        return win;
    }

    function getTicketCount() public view returns (uint256) {
        return ticketSold;
    }

    function getParticipants() public view returns (uint256) {
        return booking.length.sub(1);
    }

    function getBooking() public view returns (Book[] memory) {
        return booking;
    }

    function getClaimed() public view returns (bool) {
        return booking[depositIndex[msg.sender]].claimed;
    }
}
