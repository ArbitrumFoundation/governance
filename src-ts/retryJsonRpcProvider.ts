import { JsonRpcProvider, Networkish } from "@ethersproject/providers";
import { ConnectionInfo } from "ethers/lib/utils";

export type RetryJsonRpcProviderParams = {
  maxRetries: number
  retryInterval: number
  exponentialBase: number
}

export class RetryJsonRpcProvider extends JsonRpcProvider {
  constructor(
    url?: ConnectionInfo | string, 
    network?: Networkish, 
    public readonly retryParams: RetryJsonRpcProviderParams = {maxRetries: 10, retryInterval: 1000, exponentialBase: 2}
  ) {
    super(url, network);
  }

  private async _wait(ms: number) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  async send(method: string, params: any[]): Promise<any> {
    let retries = 0
    while (true) {
      try {
        return await super.send(method, params);
      }
      catch (e: any) {
        if (e.code !== 'TIMEOUT') throw e;

        if (retries >= this.retryParams.maxRetries) {
          throw new Error(`Max retries exceeded for ${method}`);
        }
        
        const waitDuration = this.retryParams.retryInterval * Math.pow(this.retryParams.exponentialBase, retries);

        console.warn(`${method} retry #${retries+1} in ${waitDuration}ms`);

        await this._wait(waitDuration);

        retries++;
      }
    }
  }
}
