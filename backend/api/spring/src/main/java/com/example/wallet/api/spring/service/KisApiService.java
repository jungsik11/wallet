package com.example.wallet.api.spring.service;

import com.example.wallet.api.spring.dto.KisTokenResponse;
import com.example.wallet.api.spring.dto.Stock;
import com.example.wallet.api.spring.dto.StockRankingResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;
import org.springframework.http.*;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.stream.Collectors;

@Service
public class KisApiService {

    @Value("${kis.appkey}")
    private String appKey;

    @Value("${kis.secretkey}")
    private String secretKey;

    private String accessToken;
    private long tokenExpiresAt;

    private final RestTemplate restTemplate = new RestTemplate();

    private void fetchToken() {
        String url = "https://openapi.koreainvestment.com:9443/oauth2/tokenP";
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);

        String body = "{\"grant_type\":\"client_credentials\",\"appkey\":\"" + appKey + "\",\"appsecret\":\"" + secretKey + "\"}";

        HttpEntity<String> request = new HttpEntity<>(body, headers);

        ResponseEntity<KisTokenResponse> response = restTemplate.postForEntity(url, request, KisTokenResponse.class);

        if (response.getStatusCode() == HttpStatus.OK && response.getBody() != null) {
            KisTokenResponse tokenResponse = response.getBody();
            this.accessToken = tokenResponse.getAccessToken();
            this.tokenExpiresAt = System.currentTimeMillis() + (tokenResponse.getExpiresIn() * 1000);
        } else {
            throw new RuntimeException("Failed to fetch KIS token");
        }
    }

    private String getToken() {
        if (accessToken == null || System.currentTimeMillis() >= tokenExpiresAt) {
            fetchToken();
        }
        return accessToken;
    }

    public List<Stock> getUsMarketCapRanking() {
        List<Stock> allStocks = new ArrayList<>();
        String[] exchanges = {"NYS", "NAS", "AMS"};

        for (String exchange : exchanges) {
            String url = "https://openapi.koreainvestment.com:9443/uapi/overseas-stock/v1/ranking/updown-rate?EXCD=" + exchange;
            HttpHeaders headers = new HttpHeaders();
            headers.set("authorization", "Bearer " + getToken());
            headers.set("appkey", appKey);
            headers.set("appsecret", secretKey);
            headers.set("tr_id", "HHDFS76350100");

            HttpEntity<String> entity = new HttpEntity<>(headers);

            ResponseEntity<StockRankingResponse> response = restTemplate.exchange(url, HttpMethod.GET, entity, StockRankingResponse.class);

            if (response.getStatusCode() == HttpStatus.OK && response.getBody() != null) {
                allStocks.addAll(response.getBody().getStocks());
            }
        }

        List<String> etfKeywords = List.of("S&P 500", "NASDAQ", "NYSE", "MARKET", "ETF", "ETN", "INDEX", "FUND");

        return allStocks.stream()
                .filter(stock -> {
                    boolean isEtf = etfKeywords.stream().anyMatch(keyword -> stock.getName().toUpperCase().contains(keyword));
                    return !isEtf && stock.getMarketCap() > 500_000_000_000L;
                })
                .sorted(Comparator.comparingLong(Stock::getMarketCap).reversed())
                .collect(Collectors.toList());
    }
}
