#!/usr/bin/env python
import datetime
import argparse

from pymongo import MongoClient
from bson import SON


def _get_expire_time(exp_years=1):
    d = datetime.datetime.now()
    try:
        return d.replace(year=d.year + exp_years)
    except ValueError:
        return d + (datetime.date(d.year + exp_years, 1, 1) - datetime.date(d.year, 1, 1))


def _key_processing(args):
    with MongoClient(args.mongo_uri) as client:
        db = client.get_database()

        condition = {
            'user': args.user,
            'scopes': list(set(args.scopes)),
        }
        if args.customer:
            condition['customer'] = args.customer

        if not args.update:
            res = db.keys.find_one(condition)
            if res:
                return res['key']

        db.keys.delete_many(condition)
        db.keys.insert_one(SON({
            "user": args.user,
            "key": args.key,
            "scopes": list(set(args.scopes)),
            "text": args.text or '',
            "customer": args.customer,
            "expireTime": _get_expire_time(),
            "count": 0,
            "lastUsedTime": None
        }))

    return args.key


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('-M', '--mongo-uri', dest='mongo_uri', action='store', required=True)
    parser.add_argument('-s', '--scope', dest='scopes', action='append', default=['read'])
    parser.add_argument('-t', '--text', dest='text', action='store', default=None)
    parser.add_argument('-c', '--customer', dest='customer', action='store')
    parser.add_argument('-u', '--user', dest='user', action='store', default='internal')
    parser.add_argument('--update', dest='update', action='store_true')
    parser.add_argument('key', action='store')

    args = parser.parse_args()

    if not all((s.split(':')[0] in ['read', 'write', 'admin'] for s in args.scopes)):
        raise Exception('Wrong scopes: {}'.format(', '.join(args.scopes)))

    access_key = _key_processing(args)

    print(access_key)


if __name__ == '__main__':
    main()
