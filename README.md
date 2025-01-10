# VQ

Simple slurm queue visualization tool.

## Features

- Show subset of running and pending jobs in queue
- Show user summaries of running and pending jobs with priorities

## Installation


```bash
git clone https://github.com/vivekmyers/vq
cd vq
make install
```

## Additional Configuration

Add the following to your `.bashrc` to set the partition and enable the priority tracking.

```bash
export PARTITION=savio4_gpu
export LOWPRIORITY=savio_lowprio
```

## Usage

Just run `vq` 


