# -*- coding: utf-8 -*-
import json
import os
from datetime import datetime
import requests
import yaml
from dotenv import load_dotenv

# .env 파일 로드
load_dotenv()

# KIS API URL
KIS_URLS = {
    "prod": "https://openapi.koreainvestment.com:9443",
    "vps": "https://openapivts.koreainvestment.com:29443"
}

# 토큰 저장 경로
token_tmp = os.path.join(os.path.expanduser("~"), "KIS", "config", f"KIS{datetime.today().strftime('%Y%m%d')}")

# 기본 헤더
_base_headers = {
    "Content-Type": "application/json",
    "Accept": "text/plain",
    "charset": "UTF-8",
}

def save_token(my_token, my_expired):
    """발급받은 토큰을 파일에 저장"""
    try:
        os.makedirs(os.path.dirname(token_tmp), exist_ok=True)
        valid_date = datetime.strptime(my_expired, "%Y-%m-%d %H:%M:%S")
        with open(token_tmp, "w", encoding="utf-8") as f:
            f.write(f"token: {my_token}\n")
            f.write(f"valid-date: {valid_date}\n")
    except Exception as e:
        print(f"토큰 저장 중 오류 발생: {e}")


def read_token():
    """파일에 저장된 토큰을 읽어옴"""
    try:
        if not os.path.exists(token_tmp):
            return None

        with open(token_tmp, encoding="UTF-8") as f:
            tkg_tmp = yaml.load(f, Loader=yaml.FullLoader)

        exp_dt = tkg_tmp["valid-date"]
        now_dt = datetime.now()

        if exp_dt > now_dt:
            return tkg_tmp["token"]
        else:
            return None
    except Exception as e:
        print(f"토큰 읽기 중 오류 발생: {e}")
        return None

def get_token(svr="prod"):
    """
    인증 토큰을 발급받습니다.
    - 저장된 토큰이 유효하면 해당 토큰을 반환합니다.
    - 유효한 토큰이 없으면 새로 발급받아 저장하고 반환합니다.
    """
    saved_token = read_token()
    if saved_token:
        return saved_token

    # 토큰 발급 요청
    p = {"grant_type": "client_credentials"}
    
    if svr == "prod":
        app_key = os.getenv("KIS_APPKEY")
        app_secret = os.getenv("KIS_SECRET")
    elif svr == "vps":
        app_key = os.getenv("KIS_APPKEY2")
        app_secret = os.getenv("KIS_SECRET2")
    else:
        raise ValueError("svr은 'prod' 또는 'vps'여야 합니다.")

    if not app_key or not app_secret:
        print(f".env 파일에서 {svr.upper()}용 KIS_APPKEY 또는 KIS_SECRET을 찾을 수 없습니다.")
        return None

    p["appkey"] = app_key
    p["appsecret"] = app_secret

    url = f"{KIS_URLS.get(svr)}/oauth2/tokenP"

    res = requests.post(url, data=json.dumps(p), headers=_base_headers)

    if res.status_code == 200:
        res_data = res.json()
        my_token = res_data.get("access_token")
        my_expired = res_data.get("access_token_token_expired")
        
        if my_token and my_expired:
            save_token(my_token, my_expired)
            return my_token
        else:
            print("토큰 발급 응답에 필요한 정보가 없습니다.")
            return None
    else:
        print(f"토큰 발급 실패: {res.status_code} - {res.text}")
        return None


if __name__ == '__main__':
    # 토큰 발급 테스트
    token = get_token(svr="vps") # 모의투자 토큰 발급
    if token:
        print(f"발급된 토큰: {token}")
    else:
        print("토큰 발급에 실패했습니다.")