if fs.exists("/chunk_miner.state") or fs.exists("/chunk_miner.state.bak") or fs.exists("/chunk_miner.state.tmp") then
    shell.run("/ChunkMiner.lua", "resume")
end
