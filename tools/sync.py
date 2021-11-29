from multiprocessing import Pool
import time
import csv
import os
import pprint
import subprocess as sp
import argparse
from itertools import repeat


def f(row, script):
    for k in row:
        if row[k]:
            os.environ[k] = row[k]
    return sp.run(script, capture_output=True, shell=True)


def main(script, repositories):
    inventory = []
    for repo_csv in repositories:
        with open(repo_csv, newline='') as csvfile:
            fields = ['REPO', 'TAID', 'REPOVISIBILITY', 'TITLE', 'BRANCH', 'OTHER']
            rows = csv.DictReader(csvfile,fieldnames=fields)
            for r in rows:
                inventory.append(r)
    with Pool(processes=2) as p:
        pprint.pprint(p.starmap(f, zip(inventory, repeat(script))))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('script', help='path to script to be run')
    parser.add_argument('repositories', nargs='*', default=['repositories_main.csv'], help='csv with repositories')
    args = parser.parse_args()
    main(script=args.script, repositories=args.repositories)
