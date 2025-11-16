package com.example.wallet.api.spring.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

@Data
public class Stock {
    private String name;
    private String ticker;
    private double price;
    private double rate;
    @JsonProperty("mcap")
    private long marketCap;
}