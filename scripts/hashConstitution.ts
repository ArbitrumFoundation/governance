import fs from 'fs'
import {  utils } from 'ethers'

const main = async ()=>{
    const data = await fs.readFileSync("./files/constitution.md",  'utf8');
    return utils.solidityKeccak256(["string"], [data])
}

main().then((res) => {
    console.log("Constitution hash:");
    console.log(res);
})
