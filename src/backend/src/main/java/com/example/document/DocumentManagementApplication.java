package com.example.document;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class DocumentManagementApplication {

    public static void main(String[] args) {
        // TEST AUTOMATED ROLLBACK - Uncomment to trigger crash
        throw new RuntimeException("TEST: Automated Rollback - Application intentionally crashed");
        
        // SpringApplication.run(DocumentManagementApplication.class, args);
    }
}
