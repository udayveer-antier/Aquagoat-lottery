//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "../interfaces/IBuyBack.sol";
import "./LotteryNFT.sol";
import "./LotteryOwnable.sol";

contract Lottery is LotteryOwnable, Initializable {
    using SafeMath for uint256;
    using SafeMath for uint8;
    using SafeERC20 for IERC20;

    uint8 public constant keyLengthForEachBuy = 11;
    // Allocation for first/sencond/third reward
    uint8[3] public allocation;
    // The Lottery NFT for tickets
    LotteryNFT public lotteryNFT;
    // adminAddress
    address public adminAddress;
    // maxNumber
    uint8 public maxNumber;
    // minPrice, if decimal is not 18, please reset it
    uint256 public minPrice;    
    
    
    //Array of Avaiable tokens
    IERC20[] public tokens;
    //pancake router contract address
    IUniswapV2Router02 public pancakeSwapRouter;
    //path 
    address[] public path;
    
    
    //Buyback Pool share is 25%
    uint256 public buyBackShare;
    //Buyback Pool contract
    IBuyBack public buyback;

    // =================================

    // issueId => winningNumbers[numbers]
    mapping (uint256 => uint8[4]) public historyNumbers;
    // issueId => [tokenId] 
    mapping (uint256 => uint256[]) public lotteryInfo;
    // issueId => [totalAmount, firstMatchAmount, secondMatchingAmount, thirdMatchingAmount]
    mapping (uint256 => uint256[]) public historyAmount;
    // issueId => trickyNumber => buyAmountSum
    mapping (uint256 => mapping(uint64 => uint256)) public userBuyAmountSum;
    // address => [tokenId]
    mapping (address => uint256[]) public userInfo;
    //address => issueIndex => [ticketId]
    mapping (address => mapping(uint256 => uint256[])) public currentTickets;
    //address => issueIndex
    mapping (address => uint256) public lastClaimIndex;
    //token => transfer Taxed
    mapping(address => bool) public isWhitelisted;
    //tokenAddress => blacklisted
    mapping(address => bool) public isBlacklisted;
    //token address => amount
    mapping(address => uint256) public transferTax;

    uint256 public issueIndex;
    uint256 public totalAddresses;
    uint256 public totalAmount;
    uint256 public lastTimestamp;

    uint8[4] public winningNumbers;

    // default false
    bool public drawingPhase;

    // =================================

    event TokenAdded(address indexed token, uint256 tokenId, uint256 taxAmount);
    event TokenBlacklisted(address indexed blacklistedToken, bool value);
    event Drawing(uint256 indexed issueIndex, uint8[4] winningNumbers);
    event Claim(address indexed user, uint256 tokenid, uint256 amount);
    event DevWithdraw(address indexed user, uint256 amount);
    event Reset(uint256 indexed issueIndex);
    event MultiClaim(address indexed user, uint256 amount);
    event MultiBuy(address indexed user, uint256 amount,uint8[4][] numbers);
    
    modifier onlyAdmin() {
        require(msg.sender == adminAddress, "admin: wut?");
        _;
    }

       
     // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    // Fallback function is called when msg.data is not empty
    fallback() external payable {}

    function initialize(
        LotteryNFT _lottery,
        uint256 _minPrice,
        uint8 _maxNumber,
        address _owner,
        address _adminAddress,
        address _router,
        address _buyback,
        address _weth
    ) public initializer {
        lotteryNFT = _lottery;
        minPrice = _minPrice;
        maxNumber = _maxNumber;
        buyBackShare = 250;
        adminAddress = _adminAddress;
        pancakeSwapRouter = IUniswapV2Router02(_router);
        buyback = IBuyBack(_buyback);
        lastTimestamp = block.timestamp;
        allocation = [35, 25, 15];
        initOwner(_owner);
        tokens.push(IERC20(_weth));
    }

    function whiteListTokens(address[] memory _tokens, bool isTaxed) external onlyAdmin {
        require(_tokens.length > 0, "Lottery: Invalid length");

        for (uint256 i; i < _tokens.length; i++) {
            _addToken(_tokens[i], isTaxed);
        }
    }

    function _addToken(address _token, bool isTaxed) internal {
        require(_token != address(0), "Lottery: Invalid address");
        require(!isBlacklisted[_token], "Lottery: Blacklisted");
        require(!isWhitelisted[_token], "Lottery: Already whitelisted");
        uint256 _tax;

        isWhitelisted[_token] = true;
        infiniteApprove(_token);
        tokens.push(IERC20(_token));

        if (isTaxed) {
            _tax = checkTax(_token);
        }

        emit TokenAdded(_token, tokens.length-1, _tax);

    }
    
    function blacklistToken(address _token, bool _value) external onlyAdmin {
        require(_token != address(0), "Lottery: Invalid address");
        isBlacklisted[_token] = _value;
        emit TokenBlacklisted(_token, _value);
    }
    
    function infiniteApprove(address _token) internal {
        IERC20(_token).approve(address(pancakeSwapRouter), (2**256) - 1);
    }

    //   function executeApproval(address _token) public {
    //     IERC20(_token).approve(address(pancakeSwapRouter), (2**256) - 1);
    // }
    
    function checkTax(address _token) internal returns (uint256) {
        uint256[] memory amountBNB = new uint256[](2);
        uint256[] memory tokenAmount = new uint256[](2);
        uint256[] memory amounts;
        uint256 bnbInput = 10**10;
        require(path.length == 0, "Lottery: Invalid length");
        
        path.push(address(tokens[0]));
        path.push(address(_token));

        amounts = pancakeSwapRouter.getAmountsOut(bnbInput, path);
        amountBNB[0] = address(this).balance;

        uint256 bnbMinOutputAmount = amounts[0].div(2);
        uint256 tokenMinOutAmount = amounts[1].div(2);
        
        
        tokenAmount = pancakeSwapRouter.swapExactETHForTokens{value: bnbInput}(tokenMinOutAmount, path, address(this), block.timestamp + 20*60);
        delete path;
        path.push(address(_token));
        path.push(address(tokens[0]));
        pancakeSwapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(IERC20(_token).balanceOf(address(this)), bnbMinOutputAmount, path, address(this), block.timestamp + 20*60);
        
        amountBNB[1] = address(this).balance;
        
        if (amountBNB[0] > amountBNB[1]) {
            uint256 diff = amountBNB[0] - amountBNB[1];
            transferTax[_token] = (diff.mul(100)).div(bnbInput);
        }
        
        delete path;

        return transferTax[_token];
    }

    function drawed() public view returns(bool) {
        return winningNumbers[0] != 0;
    }

    function reset() external onlyAdmin {
        require(drawed(), "drawed?");
        lastTimestamp = block.timestamp;
        totalAddresses = 0;
        winningNumbers[0] = 0;
        winningNumbers[1] = 0;
        winningNumbers[2] = 0;
        winningNumbers[3] = 0;
        drawingPhase = false;
        issueIndex = issueIndex + 1;
        emit Reset(issueIndex);
    }

    function enterDrawingPhase() external onlyAdmin {
        require(!drawed(), "Lottery: Drawed");
        drawingPhase = true;
    }

    // add externalRandomNumber to prevent node validators exploiting
    function drawing(uint256 _externalRandomNumber) external onlyAdmin {
        require(!drawed(), "reset?");
        require(drawingPhase, "enter drawing phase first");
        bytes32 _structHash;
        uint256 _randomNumber;
        uint8 _maxNumber = maxNumber;
        bytes32 _blockhash = blockhash(block.number-1);

        // waste some gas fee here
        for (uint i = 0; i < 10; i++) {
            getTotalRewards(issueIndex);
        }
        uint256 _gasleft = gasleft();

        // 1
        _structHash = keccak256(
            abi.encode(
                _blockhash,
                totalAddresses,
                _gasleft,
                _externalRandomNumber
            )
        );
        _randomNumber  = uint256(_structHash);
        assembly {_randomNumber := add(mod(_randomNumber, _maxNumber),1)}
        winningNumbers[0]=uint8(_randomNumber);
        // winningNumbers[0]=uint8(1);

        // 2
        _structHash = keccak256(
            abi.encode(
                _blockhash,
                totalAmount,
                _gasleft,
                _externalRandomNumber
            )
        );
        _randomNumber  = uint256(_structHash);
        assembly {_randomNumber := add(mod(_randomNumber, _maxNumber),1)}
        winningNumbers[1]=uint8(_randomNumber);
        // winningNumbers[1]=uint8(2);

        // 3
        _structHash = keccak256(
            abi.encode(
                _blockhash,
                lastTimestamp,
                _gasleft,
                _externalRandomNumber
            )
        );
        _randomNumber  = uint256(_structHash);
        assembly {_randomNumber := add(mod(_randomNumber, _maxNumber),1)}
        winningNumbers[2]=uint8(_randomNumber);
        // winningNumbers[2]=uint8(3);

        // 4
        _structHash = keccak256(
            abi.encode(
                _blockhash,
                _gasleft,
                _externalRandomNumber
            )
        );
        _randomNumber  = uint256(_structHash);
        assembly {_randomNumber := add(mod(_randomNumber, _maxNumber),1)}
        winningNumbers[3]=uint8(_randomNumber);
        // winningNumbers[3] = uint8(4);
        historyNumbers[issueIndex] = winningNumbers;
        historyAmount[issueIndex] = calculateMatchingRewardAmount();
        drawingPhase = false;
        emit Drawing(issueIndex, winningNumbers);
    }
    
    function  multiBuyWithToken(uint256 _listId, uint256 _price, uint8[4][] memory _numbers) external {
        address _token = address(tokens[_listId]);

        require(_token !=  address(0), "Lottery: Invalid listId");
        require(!drawed(), "drawed, can not buy now");
        require(!drawingPhase, "drawing, can not buy now");
        require(!isBlacklisted[_token], "Lottery: Blacklisted");

        uint256 ticketCount = uint256(_numbers.length);
        uint256 totalPrice  = ticketCount * _price;
        
        tokens[_listId].transferFrom(address(msg.sender), address(this), totalPrice);
        totalPrice = tokens[_listId].balanceOf(address(this));

        uint256 amount = swapToken(_token, totalPrice, ticketCount);

        for (uint256 i = 0; i < ticketCount; i++) {
            for (uint256 j = 0; j < 4; j++) {
                require (_numbers[i][j] <= maxNumber && _numbers[i][j] > 0, "exceed number scope");
            }

            uint256 tokenId = lotteryNFT.newLotteryItem(msg.sender, _numbers[i], (amount / ticketCount), issueIndex);
            lotteryInfo[issueIndex].push(tokenId);

            if (userInfo[msg.sender].length == 0) {
                totalAddresses = totalAddresses + 1;
            }

            userInfo[msg.sender].push(tokenId);
            currentTickets[msg.sender][issueIndex].push(tokenId);
            lastTimestamp = block.timestamp;
        
            uint64[keyLengthForEachBuy] memory numberIndexKey = generateNumberIndexKey(_numbers[i]);

            for (uint k = 0; k < keyLengthForEachBuy; k++) {
                userBuyAmountSum[issueIndex][numberIndexKey[k]] = userBuyAmountSum[issueIndex][numberIndexKey[k]].add(amount / ticketCount);
            }
        }

        totalAmount = totalAmount.add(amount);
        emit MultiBuy(msg.sender, totalPrice, _numbers);
    }
    
    function multiBuyWithBNB(uint8[4][] memory _numbers) payable external {
        uint256 _minPrice = _numbers.length * minPrice;
        require(msg.value >= _minPrice, "minimum value not sent");
        uint256 _price = msg.value;

        for (uint i = 0; i < _numbers.length; i++) {
            for (uint j = 0; j < 4; j++) {
                require (_numbers[i][j] <= maxNumber && _numbers[i][j] > 0, "exceed number scope");
            }
            uint256 tokenId = lotteryNFT.newLotteryItem(msg.sender, _numbers[i], _price, issueIndex);
            lotteryInfo[issueIndex].push(tokenId);
            if (userInfo[msg.sender].length == 0) {
                totalAddresses = totalAddresses + 1;
            }
            userInfo[msg.sender].push(tokenId);
            currentTickets[msg.sender][issueIndex].push(tokenId);

            lastTimestamp = block.timestamp;
            uint64[keyLengthForEachBuy] memory numberIndexKey = generateNumberIndexKey(_numbers[i]);

            for (uint k = 0; k < keyLengthForEachBuy; k++) {
                userBuyAmountSum[issueIndex][numberIndexKey[k]]=userBuyAmountSum[issueIndex][numberIndexKey[k]].add(_price);
            }
        }

        uint bbShare = (_price.mul(buyBackShare)).div(1000);
        payable(address(buyback)).transfer(bbShare);
        buyback.checkBalance();
        totalAmount = totalAmount.add(_price.sub(bbShare));
        emit MultiBuy(msg.sender, _price, _numbers);
    }

    function swapToken(address _token, uint256 _price, uint256 _ticketCount) internal returns(uint256) {
        uint256[] memory amount = new uint256[](2);
        uint256[] memory amountBNB;
        uint256 initialBalance = address(this).balance;
    
        path.push(_token);
        path.push(address(tokens[0]));
        amountBNB = pancakeSwapRouter.getAmountsOut(_price, path);
        amountBNB[1] = amountBNB[1].div(2);

        if(transferTax[_token] == 0) {
            amount = pancakeSwapRouter.swapExactTokensForETH(_price, amountBNB[1], path, address(this), block.timestamp + 20*60);
            require(amount[1] >= (minPrice.mul(_ticketCount)), "Lottery: BNB amount not sufficient");
        } else {
            pancakeSwapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(_price, amountBNB[1], path, address(this), block.timestamp + 20*60);    
            amount[1] = address(this).balance.sub(initialBalance,"Lottery: Failed swapExactTokensForETHSupportingFeeOnTransferTokens");
            require(amount[1]  >= (minPrice.mul(_ticketCount)), "Lottery: BNB amount not sufficient");
        }
        
        uint bbShare = (amount[1].mul(buyBackShare)).div(1000);
        payable(address(buyback)).transfer(bbShare);
        buyback.checkBalance();
        delete path;
        return amount[1].sub(bbShare);
    }

    function claimReward(uint256 _tokenId) external {
        require(msg.sender == lotteryNFT.ownerOf(_tokenId), "not from owner");
        require (!lotteryNFT.getClaimStatus(_tokenId), "claimed");
        uint256 reward = getRewardView(_tokenId);
        lotteryNFT.claimReward(_tokenId);

        if(reward > 0) {
            (bool success, ) = address(msg.sender).call{value: reward}("");
            require(success, "Lottery: BNB transfer failed");
        }

        totalAmount = totalAmount.sub(reward);
        lastClaimIndex[msg.sender] = issueIndex -1;
        emit Claim(msg.sender, _tokenId, reward);
    }

    function  multiClaim(uint256[] memory _tickets) external {
        uint256 totalReward = 0;
        for (uint i = 0; i < _tickets.length; i++) {
            require (msg.sender == lotteryNFT.ownerOf(_tickets[i]), "not from owner");
            require (!lotteryNFT.getClaimStatus(_tickets[i]), "claimed");
            lotteryNFT.claimReward(_tickets[i]);
            uint256 reward = getRewardView(_tickets[i]);
            if(reward>0) {
                totalReward = reward.add(totalReward);
            }
        }
        if(totalReward > 0) {
            (bool success, ) = address(msg.sender).call{value: totalReward}("");
            require(success, "Lottery: BNB transfer failed");
        }
        totalAmount = totalAmount.sub(totalReward);
        lastClaimIndex[msg.sender] = issueIndex-1;
        emit MultiClaim(msg.sender, totalReward);
    }

    function generateNumberIndexKey(uint8[4] memory number) public pure returns (uint64[keyLengthForEachBuy] memory) {
        uint64[4] memory tempNumber;
        tempNumber[0]=uint64(number[0]);
        tempNumber[1]=uint64(number[1]);
        tempNumber[2]=uint64(number[2]);
        tempNumber[3]=uint64(number[3]);

        uint64[keyLengthForEachBuy] memory result;
        result[0] = tempNumber[0]*256*256*256*256*256*256 + 1*256*256*256*256*256 + tempNumber[1]*256*256*256*256 + 2*256*256*256 + tempNumber[2]*256*256 + 3*256 + tempNumber[3];

        result[1] = tempNumber[0]*256*256*256*256 + 1*256*256*256 + tempNumber[1]*256*256 + 2*256+ tempNumber[2];
        result[2] = tempNumber[0]*256*256*256*256 + 1*256*256*256 + tempNumber[1]*256*256 + 3*256+ tempNumber[3];
        result[3] = tempNumber[0]*256*256*256*256 + 2*256*256*256 + tempNumber[2]*256*256 + 3*256 + tempNumber[3];
        result[4] = 1*256*256*256*256*256 + tempNumber[1]*256*256*256*256 + 2*256*256*256 + tempNumber[2]*256*256 + 3*256 + tempNumber[3];

        result[5] = tempNumber[0]*256*256 + 1*256+ tempNumber[1];
        result[6] = tempNumber[0]*256*256 + 2*256+ tempNumber[2];
        result[7] = tempNumber[0]*256*256 + 3*256+ tempNumber[3];
        result[8] = 1*256*256*256 + tempNumber[1]*256*256 + 2*256 + tempNumber[2];
        result[9] = 1*256*256*256 + tempNumber[1]*256*256 + 3*256 + tempNumber[3];
        result[10] = 2*256*256*256 + tempNumber[2]*256*256 + 3*256 + tempNumber[3];

        return result;
    }

    function calculateMatchingRewardAmount() internal view returns (uint256[4] memory) {
        uint64[keyLengthForEachBuy] memory numberIndexKey = generateNumberIndexKey(winningNumbers);

        uint256 totalAmout1 = userBuyAmountSum[issueIndex][numberIndexKey[0]];

        uint256 sumForTotalAmout2 = userBuyAmountSum[issueIndex][numberIndexKey[1]];
        sumForTotalAmout2 = sumForTotalAmout2.add(userBuyAmountSum[issueIndex][numberIndexKey[2]]);
        sumForTotalAmout2 = sumForTotalAmout2.add(userBuyAmountSum[issueIndex][numberIndexKey[3]]);
        sumForTotalAmout2 = sumForTotalAmout2.add(userBuyAmountSum[issueIndex][numberIndexKey[4]]);

        uint256 totalAmout2 = sumForTotalAmout2.sub(totalAmout1.mul(4));

        uint256 sumForTotalAmout3 = userBuyAmountSum[issueIndex][numberIndexKey[5]];
        sumForTotalAmout3 = sumForTotalAmout3.add(userBuyAmountSum[issueIndex][numberIndexKey[6]]);
        sumForTotalAmout3 = sumForTotalAmout3.add(userBuyAmountSum[issueIndex][numberIndexKey[7]]);
        sumForTotalAmout3 = sumForTotalAmout3.add(userBuyAmountSum[issueIndex][numberIndexKey[8]]);
        sumForTotalAmout3 = sumForTotalAmout3.add(userBuyAmountSum[issueIndex][numberIndexKey[9]]);
        sumForTotalAmout3 = sumForTotalAmout3.add(userBuyAmountSum[issueIndex][numberIndexKey[10]]);

        uint256 totalAmout3 = sumForTotalAmout3.add(totalAmout1.mul(6)).sub(sumForTotalAmout2.mul(3));

        return [totalAmount, totalAmout1, totalAmout2, totalAmout3];
    }

    function getMatchingRewardAmount(uint256 _issueIndex, uint256 _matchingNumber) public view returns (uint256) {
        return historyAmount[_issueIndex][5 - _matchingNumber];
    }

    function getTotalRewards(uint256 _issueIndex) public view returns(uint256) {
        require (_issueIndex <= issueIndex, "_issueIndex <= issueIndex");

        if(!drawed() && _issueIndex == issueIndex) {
            return totalAmount;
        }
        return historyAmount[_issueIndex][0];
    }

    function getRewardView(uint256 _tokenId) public view returns(uint256) {
        uint256 _issueIndex = lotteryNFT.getLotteryIssueIndex(_tokenId);
        uint8[4] memory lotteryNumbers = lotteryNFT.getLotteryNumbers(_tokenId);
        uint8[4] memory _winningNumbers = historyNumbers[_issueIndex];
        require(_winningNumbers[0] != 0, "not drawed");

        uint256 matchingNumber = 0;
        for (uint i = 0; i < lotteryNumbers.length; i++) {
            if (_winningNumbers[i] == lotteryNumbers[i]) {
                matchingNumber= matchingNumber +1;
            }
        }
        uint256 reward = 0;
        if (matchingNumber > 1) {
            uint256 amount = lotteryNFT.getLotteryAmount(_tokenId);
            uint256 poolAmount = getTotalRewards(_issueIndex).mul(allocation[4-matchingNumber]).div(100 - (buyBackShare/10));
            reward = amount.mul(1e12).div(getMatchingRewardAmount(_issueIndex, matchingNumber)).mul(poolAmount);
        }
        return reward.div(1e12);
    }

    //get the length of the token array
    function getTokensLength() public view returns(IERC20[] memory) {
        return tokens;
    }

    // Update admin address by the previous dev.
    function setAdmin(address _adminAddress) public onlyOwner {
        adminAddress = _adminAddress;
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function adminWithdraw(uint256 _amount) public onlyAdmin {
        (bool success, )= address(msg.sender).call{value: _amount}("");
        require(success == true,"adminWithdraw failed");
        emit DevWithdraw(msg.sender, _amount);
    }

    // Set the minimum price for one ticket
    function setMinPrice(uint256 _price) external onlyAdmin {
        minPrice = _price;
    }

    // Set the minimum price for one ticket
    function setMaxNumber(uint8 _maxNumber) external onlyAdmin {
        maxNumber = _maxNumber;
    }

    // Set the allocation for one reward
    function setAllocation(uint8 _allcation1, uint8 _allcation2, uint8 _allcation3) external onlyAdmin {
        allocation = [_allcation1, _allcation2, _allcation3];
    }
    
    function setBuyback(address _buyback) external onlyAdmin {
        require(_buyback != address(buyback),"Lottery: Same buyback address sent");
        buyback = IBuyBack(_buyback);
    }

    //Get the length of the array of tokenIds
    function getCurrentLength(address _user, uint256 _issueIndex) public view returns(uint256[] memory){
        return currentTickets[_user][_issueIndex];
    }
    
    function setLotteryNFT(LotteryNFT _nft) public onlyAdmin {
        require(lotteryNFT != _nft, "Lottery: Same address sent");
        lotteryNFT = _nft;
    }
    
    function setBuyBackShare(uint256 _value) public onlyAdmin {
        buyBackShare = _value;
    }

    function setRouterAddress(address newAddress) external onlyAdmin {
        require(newAddress !=  address(0), "Lottery: Zero address");
        pancakeSwapRouter = IUniswapV2Router02(newAddress);
    }

    function getRouter() external view returns (address) {
        return address(pancakeSwapRouter);
    }
    
    function getClaimAmount(address _user, uint start, uint end) public view returns(uint totalReward) {
        uint id = start;
        for(uint i=id; i< end; i++) {
            for(uint j=0; j< currentTickets[_user][i].length; j++) {
                totalReward += getRewardView(currentTickets[_user][i][j]);
            }
        }
    }
}