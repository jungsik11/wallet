package com.example.wallet.api.spring.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

import java.util.List;

@Data
public class StockRankingResponse {
    @JsonProperty("output2")
    private List<Stock> stocks;
}