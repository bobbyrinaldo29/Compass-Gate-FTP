//
//  RemoteFileItem.swift
//  Compass Gate FTP
//

import Foundation

enum RemoteFileType: String, Sendable {
    case file
    case directory
    case symlink

    var iconName: String {
        switch self {
        case .directory:
            return "folder.fill"
        case .file:
            return "doc.fill"
        case .symlink:
            return "link"
        }
    }
}

struct RemoteFileItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let path: String
    let type: RemoteFileType
    let size: Int64
    let permissions: String
    let owner: String
    let group: String
    let modifiedDate: Date

    var isDirectory: Bool {
        type == .directory
    }

    var isHidden: Bool {
        name.hasPrefix(".")
    }

    var formattedSize: String {
        if isDirectory { return "--" }
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useAll]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: size)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modifiedDate)
    }

    var kindDescription: String {
        if isDirectory { return "Folder" }
        if type == .symlink { return "Alias / Symlink" }
        let ext = (name as NSString).pathExtension.lowercased()
        if ext.isEmpty { return "Document" }
        return "\(ext.uppercased()) File"
    }
}


enum FileGrouping: String, CaseIterable, Identifiable, Sendable {
    case none = "None"
    case name = "Name"
    case kind = "Kind"
    case dateModified = "Date Modified"
    case size = "Size"

    var id: String { rawValue }
}

struct FileGroupSection: Identifiable {
    let id: String
    let title: String
    let items: [RemoteFileItem]
}

func groupFiles(_ files: [RemoteFileItem], by grouping: FileGrouping) -> [FileGroupSection] {
    switch grouping {
    case .none:
        return [FileGroupSection(id: "all", title: "", items: files)]

    case .name:
        let folders = files.filter { $0.isDirectory }
        let regularFiles = files.filter { !$0.isDirectory }
        var sections: [FileGroupSection] = []

        if !folders.isEmpty {
            sections.append(FileGroupSection(id: "folders", title: "Folders (\(folders.count))", items: folders))
        }

        let grouped = Dictionary(grouping: regularFiles) { file -> String in
            guard let first = file.name.first else { return "#" }
            if first.isLetter {
                return String(first).uppercased()
            }
            return "#"
        }
        let sortedKeys = grouped.keys.sorted()
        for key in sortedKeys {
            if let items = grouped[key] {
                sections.append(FileGroupSection(id: "letter-\(key)", title: key, items: items))
            }
        }
        return sections

    case .kind:
        var folders: [RemoteFileItem] = []
        var images: [RemoteFileItem] = []
        var documents: [RemoteFileItem] = []
        var code: [RemoteFileItem] = []
        var archives: [RemoteFileItem] = []
        var others: [RemoteFileItem] = []

        for file in files {
            if file.isDirectory {
                folders.append(file)
            } else {
                let ext = (file.name as NSString).pathExtension.lowercased()
                switch ext {
                case "png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "ico", "heic":
                    images.append(file)
                case "pdf", "doc", "docx", "txt", "md", "rtf", "xls", "xlsx", "ppt", "pptx", "csv":
                    documents.append(file)
                case "swift", "py", "js", "ts", "html", "css", "json", "sh", "bash", "zsh", "c", "cpp", "h", "php", "rb", "go", "rs", "sql", "yaml", "yml", "xml":
                    code.append(file)
                case "zip", "tar", "gz", "tgz", "bz2", "7z", "rar", "xz":
                    archives.append(file)
                default:
                    others.append(file)
                }
            }
        }

        var sections: [FileGroupSection] = []
        if !folders.isEmpty {
            sections.append(FileGroupSection(id: "folders", title: "Folders (\(folders.count))", items: folders))
        }
        if !documents.isEmpty {
            sections.append(FileGroupSection(id: "documents", title: "Documents (\(documents.count))", items: documents))
        }
        if !images.isEmpty {
            sections.append(FileGroupSection(id: "images", title: "Images (\(images.count))", items: images))
        }
        if !code.isEmpty {
            sections.append(FileGroupSection(id: "code", title: "Developer / Code (\(code.count))", items: code))
        }
        if !archives.isEmpty {
            sections.append(FileGroupSection(id: "archives", title: "Archives (\(archives.count))", items: archives))
        }
        if !others.isEmpty {
            sections.append(FileGroupSection(id: "others", title: "Other Files (\(others.count))", items: others))
        }
        return sections

    case .dateModified:
        let calendar = Calendar.current
        let now = Date()
        var today: [RemoteFileItem] = []
        var yesterday: [RemoteFileItem] = []
        var past7Days: [RemoteFileItem] = []
        var past30Days: [RemoteFileItem] = []
        var earlier: [RemoteFileItem] = []

        for file in files {
            if calendar.isDateInToday(file.modifiedDate) {
                today.append(file)
            } else if calendar.isDateInYesterday(file.modifiedDate) {
                yesterday.append(file)
            } else if let daysAgo = calendar.dateComponents([.day], from: file.modifiedDate, to: now).day, daysAgo <= 7 {
                past7Days.append(file)
            } else if let daysAgo = calendar.dateComponents([.day], from: file.modifiedDate, to: now).day, daysAgo <= 30 {
                past30Days.append(file)
            } else {
                earlier.append(file)
            }
        }

        var sections: [FileGroupSection] = []
        if !today.isEmpty { sections.append(FileGroupSection(id: "today", title: "Today", items: today)) }
        if !yesterday.isEmpty { sections.append(FileGroupSection(id: "yesterday", title: "Yesterday", items: yesterday)) }
        if !past7Days.isEmpty { sections.append(FileGroupSection(id: "past7", title: "Previous 7 Days", items: past7Days)) }
        if !past30Days.isEmpty { sections.append(FileGroupSection(id: "past30", title: "Previous 30 Days", items: past30Days)) }
        if !earlier.isEmpty { sections.append(FileGroupSection(id: "earlier", title: "Earlier", items: earlier)) }
        return sections

    case .size:
        var folders: [RemoteFileItem] = []
        var huge: [RemoteFileItem] = []
        var large: [RemoteFileItem] = []
        var medium: [RemoteFileItem] = []
        var small: [RemoteFileItem] = []
        var tiny: [RemoteFileItem] = []

        for file in files {
            if file.isDirectory {
                folders.append(file)
            } else {
                let bytes = file.size
                if bytes > 500 * 1024 * 1024 {
                    huge.append(file)
                } else if bytes > 50 * 1024 * 1024 {
                    large.append(file)
                } else if bytes > 1024 * 1024 {
                    medium.append(file)
                } else if bytes > 100 * 1024 {
                    small.append(file)
                } else {
                    tiny.append(file)
                }
            }
        }

        var sections: [FileGroupSection] = []
        if !folders.isEmpty { sections.append(FileGroupSection(id: "folders", title: "Folders (\(folders.count))", items: folders)) }
        if !huge.isEmpty { sections.append(FileGroupSection(id: "huge", title: "Huge (> 500 MB)", items: huge)) }
        if !large.isEmpty { sections.append(FileGroupSection(id: "large", title: "Large (50 MB – 500 MB)", items: large)) }
        if !medium.isEmpty { sections.append(FileGroupSection(id: "medium", title: "Medium (1 MB – 50 MB)", items: medium)) }
        if !small.isEmpty { sections.append(FileGroupSection(id: "small", title: "Small (100 KB – 1 MB)", items: small)) }
        if !tiny.isEmpty { sections.append(FileGroupSection(id: "tiny", title: "Tiny (< 100 KB)", items: tiny)) }
        return sections
    }
}
