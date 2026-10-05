import json
import boto3

# AWS DynamoDB client connect karein
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('resume-visitor-counter')

def lambda_handler(event, context):
    # 1. Database se current count fetch aur update karein (+1 add)
    response = table.update_item(
        Key={'id': 'visitors'},
        UpdateExpression='ADD #c :val',
        ExpressionAttributeNames={'#c': 'count'},
        ExpressionAttributeValues={':val': 1},
        ReturnValues="UPDATED_NEW"
    )
    
    # 2. Naya count value nikalein
    updated_count = int(response['Attributes']['count'])
    
    # 3. Website ko response bhejein (CORS Policy allow karne ke liye)
    return {
        'statusCode': 200,
        'headers': {
            'Access-Control-Allow-Origin': '*', # Sabhi domains se traffic accept karne ke liye
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Methods': 'GET,OPTIONS'
        },
        'body': json.dumps({'count': updated_count})
    }
