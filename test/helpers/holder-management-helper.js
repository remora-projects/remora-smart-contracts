const { expect } = require("chai");

async function calculatePayout(rwaToken, investor, amount, totalSupply) {
  const tokenBalance = await rwaToken.balanceOf(investor.address);
  return BigInt((BigInt(tokenBalance) * BigInt(amount)) / BigInt(totalSupply));
}

async function payAndCalculate(
  rwaToken,
  facilitator,
  investors,
  amounts,
  amount,
  totalSupply
) {
  await rwaToken.connect(facilitator).distributePayout(amount);
  for (let i = 0; i < investors.length; ++i) {
    amounts[i] += await calculatePayout(
      rwaToken,
      investors[i],
      BigInt(amount),
      BigInt(totalSupply)
    );
  }
}

async function checkPayouts(rwaToken, investors, amounts) {
  //checks + updates payouts
  for (let i = 0; i < investors.legnth; ++i) {
    expect(
      (await rwaToken.payoutBalance.staticCallResult(investors[i].address)).at(
        0
      )
    ).to.equal(amounts[i]);
    await rwaToken.payoutBalance(investors[i].address);
  }
}

module.exports = {
  checkPayouts,
  payAndCalculate,
};
