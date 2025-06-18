import os
from datetime import date, datatime, timedelta
import pandas as pd
from pykis import PyKis,KisAccount, KisDailyOrders
from dotenv import load_dotenv
load_dotenv()


 # 실전투자용 한국투자증권 API를 생성합니다.
kis = PyKis(
    id= os.getenv('KIS_ID'),  # HTS 로그인 ID
    account=os.getenv('KIS_ACNT01'),  # 계좌번호
    appkey=os.getenv('KIS_ACNT01_ACCESS_KEY'),  # AppKey 36자리
    secretkey=os.getenv('KIS_ACNT01_SECRET_KEY'),  # SecretKey 180자리
    keep_token=True,  # API 접속 토큰 자동 저장
)


account: KisAccount = kis.account() 

daily_orders: KisDailyOrders = account.daily_orders(
    start=date(2025, 5, 26),
    end=date(2025, 6, 6),
    country='US'
    )

order_list = []
for ord in daily_orders.orders:
    if ord.executed_qty > 0:
        acn = daily_orders.orders[0].order_number.account_number
        order_list = [{
            'date': ord.order_number.time.strftime('%Y-%m-%d %H:%M:%S'),
            'account': acn.number +'-' + acn.code,
            'order_type': ord.type,
            'ticker': ord.order_number.symbol,
            'quantity': ord.executed_qty,
            'price': ord.price,
            'amount': ord.executed_qty * ord.price,
            'fee': float(ord.executed_qty) * float(ord.price)* 0.0025
        }]+ order_list
