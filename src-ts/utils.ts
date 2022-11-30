export const wait = async (ms: number) =>
  new Promise((res) => setTimeout(res, ms));
