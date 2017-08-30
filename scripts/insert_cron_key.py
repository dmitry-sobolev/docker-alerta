#!/usr/bin/env python
import os
import datetime

from pymongo import MongoClient
from bson import SON

try:
    MONGODB_URI = os.environ.get('MONGODB_URI', os.environ['MONGO_URI'])
except KeyError:
    raise Exception('Either MONGODB_URI or MONGO_URI env variable must be set')


def _get_expire_time(exp_years=1):
    d = datetime.datetime.now()
    try:
        return d.replace(year=d.year + exp_years)
    except ValueError:
        return d + (datetime.date(d.year + exp_years, 1, 1) - datetime.date(d.year, 1, 1))


def main():
    with MongoClient(MONGODB_URI) as client:
        db = client.get_database()

        db.keys.insert_one(SON({
            "user": os.environ.get('ADMIN_USER', 'internal'),
            "key": os.environ["ADMIN_KEY"],
            "scopes": ["read", "write", "admin"],
            "text": "cron jobs",
            "expireTime": _get_expire_time(),
            "count": 0,
            "lastUsedTime": None
        }))
    print("Complete!")


if __name__ == '__main__':
    main()
