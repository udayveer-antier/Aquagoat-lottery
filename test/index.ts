import {
  Lottery, LotteryNFT,
  LotteryNFT__factory,
  Lottery__factory,
  UniswapV2Factory,
  UniswapV2Factory__factory,
  UniswapV2Router02,
  UniswapV2Router02__factory,
  WETH9,
  WETH9__factory,
  MockBEP20__factory,
  MockBEP20,
  UniswapV2Pair,
  UniswapV2Pair__factory
} from "../typechain"


import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { mineBlocks, expandTo18Decimals } from "./utilities/utilities";
import { BigNumber } from "@ethersproject/bignumber";


describe("Lottery_Test_Cases", () => {

  let owner: SignerWithAddress;
  let signers: SignerWithAddress[];
  let router: UniswapV2Router02;
  let weth: WETH9;
  let factory: UniswapV2Factory;
  let bep_ERC20: MockBEP20
  let lottery: Lottery;
  let lottery_NFT: LotteryNFT;
  let pair: UniswapV2Pair


  beforeEach(async () => {
    signers = await ethers.getSigners();
    owner = signers[0];
    weth = await new WETH9__factory(owner).deploy();
    factory = await new UniswapV2Factory__factory(owner).deploy(owner.address);
    router = await new UniswapV2Router02__factory(owner).deploy(factory.address, weth.address);

    bep_ERC20 = await new MockBEP20__factory(owner).deploy("Mtk", "mm", expandTo18Decimals(5000));
    await bep_ERC20.approve(router.address, expandTo18Decimals(2000));

    console.log(await bep_ERC20.balanceOf(owner.address));

    lottery = await new Lottery__factory(owner).deploy();
    lottery_NFT = await new LotteryNFT__factory(owner).deploy();

    pair = await new UniswapV2Pair__factory(owner).deploy();

    await router.connect(owner).addLiquidityETH(bep_ERC20.address, expandTo18Decimals(200), expandTo18Decimals(1),
      expandTo18Decimals(1), owner.address, 1679258710, { value: 10 });


    //admin is owner
    let lottery_initializd = await lottery.initialize(lottery_NFT.address, 100000000, 14, owner.address, owner.address, router.address,
      owner.address, weth.address);

    //adding tokens to the tokenId;
    await lottery.whiteListTokens([bep_ERC20.address], false);
    console.log(await lottery.getTokensLength());

    //setting admin
    await lottery.setAdmin(owner.address);
    // console.log(lottery_initializd);

  });

  it.only("Multi ticket buy with Token", async () => {
    const Pair = await factory.getPair(bep_ERC20.address, weth.address);
    const pair_instance = await new UniswapV2Pair__factory(owner).attach(Pair);

    let result = await pair_instance.getReserves();
    let reserve0 = Number(result._reserve0); // Eth amount
    let reserve1 = Number(result._reserve1); // Erc-20 Token amount

    console.log("ETH (Reserve0): ", reserve0, "   Token(Reserve1): ", reserve1);
    let min_price = 33;
    //await lottery.setMinPrice(min_price);
    //console.log(" Value of min price: ",min_price);
    //let listID = bep_ERC20.address;
    //console.log(await lottery.drawed());


    console.log(await lottery.tokens.length);
    console.log(owner.address);
    console.log(bep_ERC20.address);
    console.log(weth.address);

    console.log(" length of token ", await lottery.tokens.length);

    let lottery_number = [[2, 4, 5, 6], [7, 8, 1, 3],[7, 8, 1, 3],[7, 8, 1, 3]];
    

    // issue with the lottery_number
    await lottery.multiBuyWithToken(1, min_price, lottery_number);

  })

  it("Multi ticket buy with BNB", async () => {

  })

})