/** Router: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
* WETH: 0xc778417E063141139Fce010982780140Aa0cD5Ab
*Token1(Aquagoat): 0xa956b15259577cdFc671a813BFd66beDD3f5DF97
* usdt: 0xFe824f3549b4dCaFe3aFe7D03655a841c3d386bF
*/

pragma solidity >=0.6.6;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Buyback is VRFConsumerBase, Ownable {
    using SafeMath for uint256;
    
    address admin;
     
    bytes32 internal keyHash;
    uint256 public fee;
    //Random number generated
    uint256 public randomResult;
    //Swap of BNB to Aquagoat token
    bool public allowSwap;
    //Upper bound of the range
    uint256 public numMax;
    //Lower bound of the range
    uint256 public numMin;
    
    //pancake router contract address
    IUniswapV2Router02 public pancakeSwapRouter;
     //path 
    address[] public path;
    //WETH address
    address public WETH;
    //Aquagoat token
    address public AquaToken;
    
    //charity address
    address payable public charityAddress;
    //dev address
    address payable public devAddress;
    //distribution share of dev address and charityAddress 
    uint256 public devShare = 500; // 50%
    uint256 constant MAX_SHARE = 1000; 
    uint256 public slippage = 50;
    
    
    modifier onlyAdmin {
        require(admin == msg.sender, "Operator: caller is not the operator");
        _;
    }
    /**
     * Constructor inherits VRFConsumerBase
     * 
     * Network: BSC testnet
     * Chainlink VRF Coordinator address: 0xa555fC018435bef5A13C6c6870a9d4C11DEC329C
     * LINK token address:                0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06
     * Key Hash: 0xcaf3c3727e033261d383b315559476f48034c13b18f8cafed4d871abe5049186

     * Network: Rinkeby testnet
     * Chainlink VRF Coordinator address: 0xb3dCcb4Cf7a26f6cf6B120Cf5A73875B7BBc655B
     * LINK token address:                0x01BE23585060835E02B77ef475b0Cc51aA1e0709
     * Key Hash: 0x2ed0feb3e7fd2022120aa84fab1945545a9f2ffc9076fd6156fa96eaff4c1311
     */

     //change the address for BSC mainnet
    constructor(address _weth, address _aquaToken, address payable _charity, address payable _dev, address _router)
        VRFConsumerBase(
            0xb3dCcb4Cf7a26f6cf6B120Cf5A73875B7BBc655B, // VRF Coordinator
            0x01BE23585060835E02B77ef475b0Cc51aA1e0709  // LINK Token
        )
    {
        keyHash = 0x2ed0feb3e7fd2022120aa84fab1945545a9f2ffc9076fd6156fa96eaff4c1311;
        fee = 0.1 * 10 ** 18; // 0.1 LINK (Varies by network)
        
        admin = msg.sender;
        WETH = _weth;
        AquaToken = _aquaToken;
        path.push(_weth);
        path.push(_aquaToken);
        charityAddress= _charity;
        devAddress = _dev;
        pancakeSwapRouter = IUniswapV2Router02(_router);
        numMax = 1;//check the value before deploying
        numMin = 1;
        randomResult = 10 ** 15;
        allowSwap = true;//check what should be the default value
    }
    
      receive() external payable {}
    
    /** 
     * Requests randomness 
     */
    function getRandomNumber() public returns (bytes32 requestId) {
        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK - fill contract with faucet");
        return requestRandomness(keyHash, fee);
    }
 

    /**
     * Callback function used by VRF Coordinator
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        randomResult = ((randomness.mod(numMax)).add(numMin)) * 10**18; // get random number between 1 to 50 BNB
    }

    function checkBalance() public returns (bytes32 requestId) {
        uint256 bal = address(this).balance;
        if((bal >= randomResult) && allowSwap) {
            uint256[] memory amountOut = pancakeSwapRouter.getAmountsOut(bal, path);
            uint256 amountOutMin = (amountOut[1].mul(slippage)).div(100);
            uint256[] memory amount = new uint256[](2); 
            amount = pancakeSwapRouter.swapExactETHForTokens{value: bal}(amountOutMin, path, address(this), block.timestamp + 20*60);

            uint256 AquaBal = IERC20(AquaToken).balanceOf(address(this));
            require(AquaBal >= amount[1],"Less AquaToken received");
            IERC20(AquaToken).transfer(address(devAddress), (AquaBal.mul(devShare)).div(1000));
            //it should be charity cross check this
            IERC20(AquaToken).transfer(address(charityAddress), (AquaBal.mul(1000 - devShare)).div(1000));
            return getRandomNumber();
        }

        return requestId;
    }
    
       
    function setPath(address _weth,address _aquaToken) public onlyAdmin {
        delete path;
        WETH = _weth;
        AquaToken = _aquaToken;
        path.push(_weth);
        path.push(_aquaToken);
    }
    
    function setDevShare(uint256 _share) public onlyAdmin {
        require(_share <= MAX_SHARE, "Share value exceeded" );
        devShare = _share;
    }
    
    function setAdmin(address _admin) public onlyAdmin {
        admin = _admin;
    }
    
    function changeSwapAllowance(bool _status) public onlyAdmin {
        require(_status != allowSwap, "");
        allowSwap = _status;
    } 
    
    function setNumMax(uint256 _num) public onlyAdmin {
        require(_num >= numMin, "Buyback: Number less than numMin'");
        numMax = _num;
    }
    
    function setNumMin(uint256 _num) public onlyAdmin {
        require(_num > 0, "Buyback: Number less than Zero");
        numMin = _num;
    }
    
    function setAquagoatToken(address _token) public onlyAdmin {
        require(_token != address(0),"Buyback: Zero address is sent");
        AquaToken = _token;
    }

    function setRandomResult(uint256 newValue) external onlyAdmin {
        require(newValue > 0, "Buyback: Invalid value");
        randomResult = newValue;
    }
    
    function adminWithdrawal() external onlyAdmin {
        uint256 bnbBal = balance();
        if (bnbBal > 0) {
            payable(admin).transfer(balance());
        }
    }

    function withdwawLink() external onlyAdmin {
        uint256 linkBal = LINK.balanceOf(address(this));
        if (linkBal > 0) {
            LINK.transfer(admin, linkBal);
        } 
    }
    
    function balance() view public returns(uint256){
        return address(this).balance;
    }
}