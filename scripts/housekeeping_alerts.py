#!/usr/bin/env python
import argparse
import os
import datetime

from pymongo import MongoClient
from bson import SON


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('-M', '--mongo-uri', dest='mongo_uri', action='store', required=True)
    args = parser.parse_args()

    def _update_alert(alert):
        db.alerts.update_one({'_id': alert['_id']}, {
            '$set': {'status': 'expired'},
            '$push': SON({
                'history': {
                    'event': alert['event'],
                    'status': 'expired',
                    'text': "alert timeout status change",
                    'id': alert['lastReceiveId'],
                    'updateTime': now
                }
            })
        }, False, True)

    with MongoClient(args.mongo_uri) as client:
        db = client.get_database()

        now = datetime.datetime.now()
        two_hrs_ago = now - datetime.timedelta(hours=2)
        twelve_hrs_ago = now - datetime.timedelta(hours=12)

        # mark timed out alerts as EXPIRED and update alert history
        res = db.alerts.aggregate([
            {'$project': {'event': 1, 'status': 1, 'lastReceiveId': 1, 'timeout': 1,
                          'expireTime': {'$add': ["$lastReceiveTime", {'$multiply': ["$timeout", 1000]}]}}},
            {'$match': SON({'status': {'$ne': 'expired'}, 'expireTime': {'$lt': now}, 'timeout': {'$ne': 0}})}
        ])
        map(_update_alert, res)

        # delete CLOSED or EXPIRED alerts older than 2 hours
        db.alerts.delete_many({
            'status': {'$in': ['closed', 'expired']},
            'lastReceiveTime': SON({'$lt': two_hrs_ago})
        })

        db.alerts.delete_many({
            'severity': 'informational',
            'lastReceiveTime': SON({'$lt': twelve_hrs_ago})
        })

    print("Complete")


if __name__ == '__main__':
    main()
