# -*- coding: utf-8 -*-
import json
import os
import requests
import pandas as pd
import logging
from typing import Tuple, Optional

from kis_token_manager import get_token

# KIS API URL
KIS_URLS = {
    "prod": "https://openapi.koreainvestment.com:9443",
    "vps": "https://openapivts.koreainvestment.com:29443"
}

# 기본 헤더
_base_headers = {
    "Content-Type": "application/json",
    "Accept": "text/plain",
    "charset": "UTF-8",
}

def _url_fetch(api_url, tr_id, tr_cont, params, svr="vps"):
    token = get_token(svr)
    if not token:
        raise Exception("토큰 발급 실패")

    headers = _base_headers.copy()
    headers["authorization"] = f"Bearer {token}"
    headers["appkey"] = os.getenv("KIS_APPKEY2") if svr == "vps" else os.getenv("KIS_APPKEY")
    headers["appsecret"] = os.getenv("KIS_SECRET2") if svr == "vps" else os.getenv("KIS_SECRET")
    headers["tr_id"] = tr_id
    headers["custtype"] = "P"
    headers["tr_cont"] = tr_cont

    url = f"{KIS_URLS.get(svr)}{api_url}"

    res = requests.get(url, headers=headers, params=params)

    if res.status_code == 200:
        return res.json()
    else:
        raise Exception(f"API 요청 실패: {res.status_code} - {res.text}")

def get_overseas_stock_volume_rank(
        excd: str,  # 거래소명
        nday: str,  # N분전콤보값
        vol_rang: str,  # 거래량조건
        gubn: str,  # [필수] 상승율/하락율 구분
        keyb: str = "",  # NEXT KEY BUFF
        auth: str = "",  # 사용자권한정보
        prc1: str = "",  # 가격 필터 시작
        prc2: str = "",  # 가격 필터 종료
        tr_cont: str = "",  # 연속거래여부
        dataframe1: Optional[pd.DataFrame] = None,  # 누적 데이터프레임1
        dataframe2: Optional[pd.DataFrame] = None,  # 누적 데이터프레임2
        depth: int = 0,  # 내부 재귀깊이 (자동관리)
        max_depth: int = 10  # 최대 재귀 횟수 제한
) -> Tuple[pd.DataFrame, pd.DataFrame]:
    """
    해외주식 거래량순위 API를 호출하여 DataFrame으로 반환합니다.
    """

    # 필수 파라미터 검증
    if excd == "":
        raise ValueError(
            "excd is required (e.g. 'NYS:뉴욕, NAS:나스닥, AMS:아멕스, HKS:홍콩, SHS:상해, SZS:심천, HSX:호치민, HNX:하노이, TSE:도쿄')")

    if nday == "":
        raise ValueError(
            "nday is required (e.g. '0:당일, 1:2일전, 2:3일전, 3:5일전, 4:10일전, 5:20일전, 6:30일전, 7:60일전, 8:120일전, 9:1년전')")

    if vol_rang == "":
        raise ValueError(
            "vol_rang is required (e.g. '0:전체, 1:1백주이상, 2:1천주이상, 3:1만주이상, 4:10만주이상, 5:100만주이상, 6:1000만주이상')")

    if depth > max_depth:
        logging.warning("Max recursive depth reached.")
        if dataframe1 is None and dataframe2 is None:
            return pd.DataFrame(), pd.DataFrame()
        else:
            return dataframe1 if dataframe1 is not None else pd.DataFrame(), dataframe2 if dataframe2 is not None else pd.DataFrame()

    tr_id = "HHDFS76310010"  # 해외주식 거래량순위

    api_url = "/uapi/overseas-stock/v1/ranking/trade-vol"

    params = {
        "EXCD": excd,
        "NDAY": nday,
        "VOL_RANG": vol_rang,
        "GUBN": gubn,
        "KEYB": keyb,
        "AUTH": auth,
        "PRC1": prc1,
        "PRC2": prc2
    }

    res = _url_fetch(api_url, tr_id, tr_cont, params)

    # output1 처리
    current_data1 = pd.DataFrame(res.get('output1'), index=[0])
    if dataframe1 is not None:
        dataframe1 = pd.concat([dataframe1, current_data1], ignore_index=True)
    else:
        dataframe1 = current_data1

    # output2 처리
    current_data2 = pd.DataFrame(res.get('output2'))
    if dataframe2 is not None:
        dataframe2 = pd.concat([dataframe2, current_data2], ignore_index=True)
    else:
        dataframe2 = current_data2

    tr_cont = res.get('tr_cont')

    if tr_cont in ["M", "F"]:  # 다음 페이지 존재
        logging.info("Call Next page...")
        # ka.smart_sleep()  # 시스템 안정적 운영을 위한 지연 (필요시 추가)
        return get_overseas_stock_volume_rank(
            excd, nday, vol_rang, keyb, auth, prc1, prc2, "N", dataframe1, dataframe2, depth + 1, max_depth
        )
    else:
        logging.info("Data fetch complete.")
        return dataframe1, dataframe2

def get_overseas_stock_updown_rate(
        excd: str,  # [필수] 거래소명
        nday: str,  # [필수] N일자값
        gubn: str,  # [필수] 상승율/하락율 구분
        vol_rang: str,  # [필수] 거래량조건
        keyb: str = "",  # NEXT KEY BUFF
        tr_cont: str = "",  # 연속거래여부
        dataframe1: Optional[pd.DataFrame] = None,  # 누적 데이터프레임1
        dataframe2: Optional[pd.DataFrame] = None,  # 누적 데이터프레임2
        depth: int = 0,  # 내부 재귀깊이 (자동관리)
        max_depth: int = 10  # 최대 재귀 횟수 제한
) -> Tuple[pd.DataFrame, pd.DataFrame]:
    """
    해외주식 상승률/하락률 순위를 조회합니다.
    """

    # 필수 파라미터 검증
    if excd == "":
        raise ValueError(
            "excd is required (e.g. 'NYS:뉴욕, NAS:나스닥, AMS:아멕스, HKS:홍콩, SHS:상해, SZS:심천, HSX:호치민, HNX:하노이, TSE:도쿄')")

    if nday == "":
        raise ValueError("nday is required (e.g. '0:당일, 1:2일, 2:3일, 3:5일, 4:10일, 5:20일전, 6:30일, 7:60일, 8:120일, 9:1년')")

    if gubn == "":
        raise ValueError("gubn is required (e.g. '0:하락율, 1:상승율')")

    if vol_rang == "":
        raise ValueError(
            "vol_rang is required (e.g. '0:전체, 1:1백주이상, 2:1천주이상, 3:1만주이상, 4:10만주이상, 5:100만주이상, 6:1000만주이상')")

    if depth > max_depth:
        logging.warning("Max recursive depth reached.")
        if dataframe1 is None and dataframe2 is None:
            return pd.DataFrame(), pd.DataFrame()
        else:
            return dataframe1 if dataframe1 is not None else pd.DataFrame(), dataframe2 if dataframe2 is not None else pd.DataFrame()

    tr_id = "HHDFS76290000"

    api_url = "/uapi/overseas-stock/v1/ranking/updown-rate"

    params = {
        "EXCD": excd,
        "NDAY": nday,
        "GUBN": gubn,
        "VOL_RANG": vol_rang,
        "KEYB": keyb
    }

    res = _url_fetch(api_url, tr_id, tr_cont, params)

    # output1 처리
    current_data1 = pd.DataFrame(res.get('output1'), index=[0])
    if dataframe1 is not None:
        dataframe1 = pd.concat([dataframe1, current_data1], ignore_index=True)
    else:
        dataframe1 = current_data1

    # output2 처리
    current_data2 = pd.DataFrame(res.get('output2'))
    if dataframe2 is not None:
        dataframe2 = pd.concat([dataframe2, current_data2], ignore_index=True)
    else:
        dataframe2 = current_data2

    tr_cont = res.get('tr_cont')

    if tr_cont in ["M", "F"]:  # 다음 페이지 존재
        logging.info("Call Next page...")
        return get_overseas_stock_updown_rate(
            excd, nday, gubn, vol_rang, keyb, "N", dataframe1, dataframe2, depth + 1, max_depth
        )
    else:
        logging.info("Data fetch complete.")
        return dataframe1, dataframe2

if __name__ == '__main__':
    from dotenv import load_dotenv
    load_dotenv()
    # 해외주식 거래량 순위 조회 테스트
    df1, df2 = get_overseas_stock_volume_rank(excd="NAS", nday="0", gubn="1", vol_rang="5")
    print("--- output1 ---")
    print(df1)
    print("--- output2 ---")
    print(df2)
    df1.to_csv('df1.csv')
    df2.to_csv('df2.csv')