package com.example.document.dto;

import java.time.LocalDateTime;

public class DocumentDTO {

    private Long id;
    private String name;
    private LocalDateTime uploadTime;
    private String fileName;

    public DocumentDTO() {}

    public DocumentDTO(Long id, String name, LocalDateTime uploadTime, String fileName) {
        this.id = id;
        this.name = name;
        this.uploadTime = uploadTime;
        this.fileName = fileName;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }

    public LocalDateTime getUploadTime() { return uploadTime; }
    public void setUploadTime(LocalDateTime uploadTime) { this.uploadTime = uploadTime; }

    public String getFileName() { return fileName; }
    public void setFileName(String fileName) { this.fileName = fileName; }
}
