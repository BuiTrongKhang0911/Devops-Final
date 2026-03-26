package com.example.document.service;

import com.example.document.dto.DocumentDTO;
import com.example.document.dto.DocumentUpdateRequest;
import com.example.document.entity.Document;
import com.example.document.repository.DocumentRepository;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.Resource;
import org.springframework.core.io.UrlResource;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.net.MalformedURLException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
public class DocumentService {

    private final DocumentRepository documentRepository;
    private final Path uploadPath;

    public DocumentService(DocumentRepository documentRepository,
                           @Value("${app.upload.dir}") String uploadDir) {
        this.documentRepository = documentRepository;
        this.uploadPath = Paths.get(uploadDir).toAbsolutePath().normalize();
        try {
            Files.createDirectories(this.uploadPath);
        } catch (IOException e) {
            throw new RuntimeException("Could not create upload directory", e);
        }
    }

    // Upload document
    public DocumentDTO uploadDocument(String name, MultipartFile file) {
        String originalFileName = file.getOriginalFilename();
        String storedFileName = UUID.randomUUID() + "_" + originalFileName;

        try {
            Path targetLocation = uploadPath.resolve(storedFileName);
            Files.copy(file.getInputStream(), targetLocation, StandardCopyOption.REPLACE_EXISTING);

            Document doc = new Document();
            doc.setName(name);
            doc.setFileName(storedFileName);
            doc.setUploadTime(LocalDateTime.now());

            Document saved = documentRepository.save(doc);
            return toDTO(saved);
        } catch (IOException e) {
            throw new RuntimeException("Failed to store file: " + originalFileName, e);
        }
    }

    // Get all documents
    public List<DocumentDTO> getAllDocuments() {
        return documentRepository.findAll()
                .stream()
                .map(this::toDTO)
                .collect(Collectors.toList());
    }

    // Get document by ID
    public DocumentDTO getDocumentById(Long id) {
        Document doc = documentRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Document not found with id: " + id));
        return toDTO(doc);
    }

    // Download file as Resource
    public Resource downloadFile(Long id) {
        Document doc = documentRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Document not found with id: " + id));

        try {
            Path filePath = uploadPath.resolve(doc.getFileName()).normalize();
            Resource resource = new UrlResource(filePath.toUri());

            if (resource.exists() && resource.isReadable()) {
                return resource;
            } else {
                throw new RuntimeException("File not found on disk: " + doc.getFileName());
            }
        } catch (MalformedURLException e) {
            throw new RuntimeException("File not found: " + doc.getFileName(), e);
        }
    }

    // Get original filename for download
    public String getOriginalFileName(Long id) {
        Document doc = documentRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Document not found with id: " + id));
        return doc.getFileName().substring(doc.getFileName().indexOf("_") + 1);
    }

    // Update document
    public DocumentDTO updateDocument(Long id, DocumentUpdateRequest request, MultipartFile newFile) {
        Document doc = documentRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Document not found with id: " + id));

        // Update name
        if (request.getName() != null && !request.getName().isBlank()) {
            doc.setName(request.getName());
        }

        // Update file if provided
        if (newFile != null && !newFile.isEmpty()) {
            try {
                // Delete old file
                Path oldFilePath = uploadPath.resolve(doc.getFileName());
                Files.deleteIfExists(oldFilePath);

                // Save new file
                String storedFileName = UUID.randomUUID() + "_" + newFile.getOriginalFilename();
                Path newFilePath = uploadPath.resolve(storedFileName);
                Files.copy(newFile.getInputStream(), newFilePath, StandardCopyOption.REPLACE_EXISTING);

                doc.setFileName(storedFileName);
            } catch (IOException e) {
                throw new RuntimeException("Failed to update file", e);
            }
        }

        Document updated = documentRepository.save(doc);
        return toDTO(updated);
    }

    // Delete document
    public void deleteDocument(Long id) {
        Document doc = documentRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Document not found with id: " + id));

        try {
            Path filePath = uploadPath.resolve(doc.getFileName());
            Files.deleteIfExists(filePath);
        } catch (IOException e) {
            System.err.println("Warning: Could not delete file from disk: " + doc.getFileName());
        }

        documentRepository.delete(doc);
    }

    // Convert Entity to DTO
    private DocumentDTO toDTO(Document doc) {
        String originalFileName = doc.getFileName().substring(doc.getFileName().indexOf("_") + 1);
        return new DocumentDTO(doc.getId(), doc.getName(), doc.getUploadTime(), originalFileName);
    }
}
