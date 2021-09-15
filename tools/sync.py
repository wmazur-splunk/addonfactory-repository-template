from multiprocessing import Pool
import time
import csv
import os
import pprint
import subprocess as sp
def f(row):
    for k in row:
        if row[k]:
            os.environ[k] = row[k]
    return sp.run("tools/sync.sh",capture_output=True,shell=True)
    

if __name__ == '__main__':
    inventory = []
    with open('repo_try.csv', newline='') as csvfile:
        fields = ['REPO', 'TAID', 'REPOVISIBILITY', 'TITLE', 'BRANCH', 'OTHER']
        rows = csv.DictReader(csvfile,fieldnames=fields)
        for r in rows:
            inventory.append(r)
    with Pool(processes=4) as p:
        pprint.pprint(p.map(f, inventory))