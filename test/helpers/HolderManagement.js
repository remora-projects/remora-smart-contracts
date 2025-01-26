const { expect } = require("chai");

async function calculateRent(rwaToken, investor, amount, totalSupply) {
  const tokenBalance = await rwaToken.balanceOf(investor.address);
  return BigInt((BigInt(tokenBalance) * BigInt(amount)) / BigInt(totalSupply));
}

async function payAndCalculate(
  rwaToken,
  investors,
  amounts,
  amount,
  totalSupply
) {
  await rwaToken.distributeRentalPayments(amount);
  for (let i = 0; i < investors.length; ++i) {
    amounts[i] += await calculateRent(
      rwaToken,
      investors[i],
      BigInt(amount),
      BigInt(totalSupply)
    );
  }
}

async function checkRents(rwaToken, investors, amounts) {
  //checks + updates rents
  for (let i = 0; i < investors.legnth; ++i) {
    expect(
      (await rwaToken.rentBalance.staticCallResult(investors[i].address)).at(0)
    ).to.equal(amounts[i]);
    await rwaToken.rentBalance(investors[i].address);
  }
}

module.exports = {
  checkRents,
  payAndCalculate,
};
