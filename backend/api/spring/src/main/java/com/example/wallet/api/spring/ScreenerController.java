package com.example.wallet.api.spring;

import com.example.wallet.api.spring.dto.Stock;
import com.example.wallet.api.spring.service.KisApiService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/screener")
public class ScreenerController {

    private final KisApiService kisApiService;

    public ScreenerController(KisApiService kisApiService) {
        this.kisApiService = kisApiService;
    }

    @GetMapping("/us-market-cap-ranking")
    public List<Stock> getUsMarketCapRanking() {
        return kisApiService.getUsMarketCapRanking();
    }
}