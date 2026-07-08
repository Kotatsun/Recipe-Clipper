import Foundation
import UIKit

struct RecipePDFSnapshot {
    let title: String
    let summary: String
    let ingredients: [String]
    let instructions: [String]
    let note: String
    let tags: [String]
    let sourceURL: URL?
    let sourceName: String?
    let sourceType: String?
    let rating: Int?
    let isFavorite: Bool
    let wantsToCookAgain: Bool
    let cookedCount: Int
    let lastCookedDate: Date?
    let imageData: Data?
    let cookLogs: [CookLogPDFSnapshot]
}

struct CookLogPDFSnapshot {
    let cookedDate: Date
    let rating: Int?
    let memo: String
    let arrangement: String
    let nextImprovement: String
    let imageData: Data?
}

@MainActor
final class RecipePDFExporter {
    func exportAll(recipes: [Recipe]) throws -> URL {
        let snapshots = recipes
            .sorted { $0.createdAt < $1.createdAt }
            .map(RecipePDFSnapshot.init(recipe:))
        let outputURL = try Self.outputURL(fileName: "RecipeClipper_Backup_\(Self.fileDateText()).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: PDFRecipeRenderer.pageRect)

        try renderer.writePDF(to: outputURL) { context in
            let drawer = PDFRecipeRenderer(context: context)
            drawer.drawCover(recipeCount: snapshots.count, exportedAt: Date())
            snapshots.forEach { drawer.drawRecipePage(snapshot: $0) }
        }

        return outputURL
    }

    func exportSingle(recipe: Recipe) throws -> URL {
        let snapshot = RecipePDFSnapshot(recipe: recipe)
        let title = Self.safeFileTitle(from: snapshot.title)
        let outputURL = try Self.outputURL(fileName: "RecipeClipper_\(title)_\(Self.fileDateText()).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: PDFRecipeRenderer.pageRect)

        try renderer.writePDF(to: outputURL) { context in
            let drawer = PDFRecipeRenderer(context: context)
            drawer.drawRecipePage(snapshot: snapshot)
        }

        return outputURL
    }

    private static func outputURL(fileName: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecipeClipperPDF", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let uniquePrefix = UUID().uuidString
        return directory.appendingPathComponent("\(uniquePrefix)-\(fileName)")
    }

    private static func fileDateText(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func safeFileTitle(from title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Recipe" }

        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:\n\r\t")
            .union(.controlCharacters)
        let sanitized = trimmed
            .components(separatedBy: invalidCharacters)
            .joined(separator: "_")
            .replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ._"))

        let fallback = sanitized.isEmpty ? "Recipe" : sanitized
        return String(fallback.prefix(60))
    }
}

private extension RecipePDFSnapshot {
    @MainActor
    init(recipe: Recipe) {
        let sourceURL = recipe.sourceURL ?? URL(string: recipe.normalizedSourceURLString)
        title = recipe.title
        summary = recipe.summary
        ingredients = recipe.ingredientLines
        instructions = recipe.instructionLines
        note = recipe.notes
        tags = recipe.tags
        self.sourceURL = sourceURL
        sourceName = recipe.sourceHost.isEmpty ? nil : recipe.sourceHost
        sourceType = recipe.sourceKind.displayName
        rating = recipe.rating > 0 ? recipe.rating : nil
        isFavorite = recipe.isFavorite
        wantsToCookAgain = recipe.wantsRemake
        cookedCount = recipe.cookLogs.count
        lastCookedDate = recipe.lastCookedAt
        imageData = Self.compressedImageData(fileName: recipe.localImageFileName, maxPixelLength: 1_400)
        cookLogs = recipe.cookLogs
            .sorted { $0.cookedAt > $1.cookedAt }
            .map(CookLogPDFSnapshot.init(cookLog:))
    }

    static func compressedImageData(fileName: String?, maxPixelLength: CGFloat) -> Data? {
        // ImageIOのサムネイル生成でフル解像度のデコードを避ける
        guard let image = ImageStore.thumbnail(for: fileName, maxPixelLength: maxPixelLength) else { return nil }
        return image.jpegData(compressionQuality: 0.78)
    }
}

private extension CookLogPDFSnapshot {
    @MainActor
    init(cookLog: CookLog) {
        cookedDate = cookLog.cookedAt
        rating = cookLog.rating > 0 ? cookLog.rating : nil
        memo = cookLog.memo
        arrangement = cookLog.arrangementMemo
        nextImprovement = cookLog.improvementMemo
        imageData = RecipePDFSnapshot.compressedImageData(fileName: cookLog.localImageFileName, maxPixelLength: 700)
    }
}

private final class PDFRecipeRenderer {
    static let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)

    private let context: UIGraphicsPDFRendererContext
    private let margin = UIEdgeInsets(top: 38, left: 40, bottom: 48, right: 40)
    private let appIcon = PDFRecipeRenderer.loadAppIcon()
    private let headerLogo = UIImage(named: "PDFHeaderLogo")
    private var y: CGFloat = 38
    private var pageNumber = 0

    private enum Palette {
        static let paper = UIColor(red: 0.985, green: 0.985, blue: 0.975, alpha: 1)
        static let ink = UIColor(red: 0.10, green: 0.095, blue: 0.085, alpha: 1)
        static let mutedInk = UIColor(red: 0.36, green: 0.35, blue: 0.32, alpha: 1)
        static let hairline = UIColor(red: 0.82, green: 0.80, blue: 0.75, alpha: 1)
        static let accent = UIColor(red: 0.86, green: 0.23, blue: 0.15, alpha: 1)
        static let leaf = UIColor(red: 0.13, green: 0.42, blue: 0.33, alpha: 1)
        static let warmPanel = UIColor(red: 1.00, green: 0.95, blue: 0.84, alpha: 1)
        static let coolPanel = UIColor(red: 0.90, green: 0.96, blue: 0.94, alpha: 1)
        static let link = UIColor(red: 0.05, green: 0.34, blue: 0.72, alpha: 1)
        static let white = UIColor.white
    }

    private var contentWidth: CGFloat {
        Self.pageRect.width - margin.left - margin.right
    }

    init(context: UIGraphicsPDFRendererContext) {
        self.context = context
    }

    func drawCover(recipeCount: Int, exportedAt: Date) {
        beginPage()
        drawCoverArtwork()
        y = 255
        drawText(
            "RecipeClipper レシピバックアップ",
            font: .boldSystemFont(ofSize: 28),
            color: Palette.ink,
            lineSpacing: 4,
            spacingAfter: 22
        )
        drawMetricRow(items: [
            ("書き出し日", Self.displayDate(exportedAt)),
            ("レシピ件数", "\(recipeCount)件")
        ])
    }

    func drawRecipePage(snapshot: RecipePDFSnapshot) {
        beginPage()
        drawRecipeHeader(snapshot: snapshot)

        drawImage(snapshot.imageData, maxHeight: 230, spacingAfter: 14)

        let metaText = metadataText(for: snapshot)
        if !metaText.isEmpty {
            drawMetaBand(metaText)
        }

        drawSection(title: "概要", body: snapshot.summary, style: .highlight)
        if let sourceURL = snapshot.sourceURL {
            drawSection(title: "元URL", body: sourceURL.absoluteString, url: sourceURL, style: .compact)
        }
        drawListSection(title: "材料", items: snapshot.ingredients, prefix: "・ ")
        drawListSection(title: "作り方", items: snapshot.instructions, isNumbered: true)
        drawSection(title: "自分メモ", body: snapshot.note, style: .highlight)
        drawSection(title: "タグ", body: snapshot.tags.joined(separator: ", "), style: .compact)
        drawCookLogs(snapshot.cookLogs)
    }

    private func drawRecipeHeader(snapshot: RecipePDFSnapshot) {
        let title = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "無題のレシピ" : snapshot.title
        drawHeaderLogo()
        drawText(
            title,
            font: .boldSystemFont(ofSize: 25),
            color: Palette.ink,
            lineSpacing: 4,
            spacingAfter: 8
        )
        drawAccentRule(width: 74, thickness: 4, spacingAfter: 14)
    }

    private func beginPage() {
        context.beginPage()
        pageNumber += 1
        Palette.paper.setFill()
        UIBezierPath(rect: Self.pageRect).fill()
        drawFooter()
        y = margin.top
    }

    private func drawCoverArtwork() {
        Palette.leaf.setFill()
        UIBezierPath(rect: CGRect(x: 0, y: 0, width: Self.pageRect.width, height: 160)).fill()

        Palette.accent.setFill()
        UIBezierPath(
            roundedRect: CGRect(x: margin.left, y: 72, width: 118, height: 118),
            cornerRadius: 26
        ).fill()

        drawAppIcon(
            in: CGRect(x: margin.left + 18, y: 90, width: 82, height: 82),
            cornerRadius: 19,
            fallbackBackground: Palette.warmPanel
        )

        drawDirectText(
            "PDF BACKUP",
            rect: CGRect(x: margin.left, y: 205, width: contentWidth, height: 24),
            font: .boldSystemFont(ofSize: 11),
            color: Palette.accent,
            alignment: .left
        )
    }

    private func drawAppIcon(in rect: CGRect, cornerRadius: CGFloat, fallbackBackground: UIColor) {
        if let appIcon {
            drawRoundedImage(appIcon, in: rect, cornerRadius: cornerRadius)
            return
        }

        fallbackBackground.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).fill()
        Palette.leaf.setFill()
        UIBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.22)).fill()
        Palette.accent.setFill()
        UIBezierPath(
            roundedRect: CGRect(
                x: rect.midX - rect.width * 0.07,
                y: rect.minY + rect.height * 0.18,
                width: rect.width * 0.14,
                height: rect.height * 0.64
            ),
            cornerRadius: rect.width * 0.07
        ).fill()
    }

    private func drawHeaderLogo() {
        let maxSize = CGSize(width: 220, height: 44)
        if let headerLogo, headerLogo.size.width > 0, headerLogo.size.height > 0 {
            let scale = min(maxSize.width / headerLogo.size.width, maxSize.height / headerLogo.size.height)
            let drawSize = CGSize(width: headerLogo.size.width * scale, height: headerLogo.size.height * scale)
            let rect = CGRect(x: margin.left, y: y, width: drawSize.width, height: drawSize.height)
            headerLogo.draw(in: rect)
            y += drawSize.height + 16
            return
        }

        drawDirectText(
            "RecipeClipper",
            rect: CGRect(x: margin.left, y: y, width: maxSize.width, height: 18),
            font: .systemFont(ofSize: 13, weight: .bold),
            color: Palette.accent,
            alignment: .left
        )
        y += 32
    }

    private func drawMetricRow(items: [(String, String)]) {
        let gap: CGFloat = 12
        let itemWidth = (contentWidth - gap * CGFloat(items.count - 1)) / CGFloat(items.count)
        let height: CGFloat = 66
        ensureSpace(height + 18)

        for (index, item) in items.enumerated() {
            let x = margin.left + CGFloat(index) * (itemWidth + gap)
            let rect = CGRect(x: x, y: y, width: itemWidth, height: height)
            Palette.coolPanel.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 12).fill()
            drawDirectText(
                item.0,
                rect: CGRect(x: rect.minX + 14, y: rect.minY + 12, width: rect.width - 28, height: 16),
                font: .systemFont(ofSize: 10, weight: .semibold),
                color: Palette.mutedInk,
                alignment: .left
            )
            drawDirectText(
                item.1,
                rect: CGRect(x: rect.minX + 14, y: rect.minY + 30, width: rect.width - 28, height: 26),
                font: .boldSystemFont(ofSize: 17),
                color: Palette.ink,
                alignment: .left
            )
        }
        y += height + 18
    }

    private enum SectionStyle {
        case normal
        case compact
        case highlight
    }

    private func drawSection(title: String, body: String, url: URL? = nil, style: SectionStyle = .normal) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        ensureSpace(68)

        if style == .highlight {
            drawSoftPanelStart()
        }

        drawSectionTitle(title, compact: style == .compact)
        if let url {
            drawLinkedText(trimmed, url: url)
        } else {
            let fontSize: CGFloat = style == .compact ? 11.2 : 12.2
            drawText(trimmed, font: .systemFont(ofSize: fontSize), color: Palette.ink, lineSpacing: 2.4, spacingAfter: style == .compact ? 10 : 12)
        }
    }

    private func drawListSection(title: String, items: [String], prefix: String = "", isNumbered: Bool = false) {
        let cleanedItems = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleanedItems.isEmpty else { return }

        let body = cleanedItems.enumerated()
            .map { index, item in
                isNumbered ? "\(index + 1). \(item)" : "\(prefix)\(item)"
            }
            .joined(separator: "\n")
        drawSection(title: title, body: body)
    }

    private func drawSectionTitle(_ title: String, compact: Bool) {
        ensureSpace(26)
        let barRect = CGRect(x: margin.left, y: y + 2, width: 5, height: compact ? 14 : 17)
        Palette.accent.setFill()
        UIBezierPath(roundedRect: barRect, cornerRadius: 2).fill()

        drawDirectText(
            title,
            rect: CGRect(x: margin.left + 12, y: y, width: contentWidth - 12, height: 22),
            font: .boldSystemFont(ofSize: compact ? 12.5 : 14),
            color: Palette.ink,
            alignment: .left
        )
        y += compact ? 22 : 25
    }

    private func drawSoftPanelStart() {
        let rect = CGRect(x: margin.left - 12, y: y - 8, width: contentWidth + 24, height: 8)
        Palette.warmPanel.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 8).fill()
    }

    private func drawAccentRule(width: CGFloat, thickness: CGFloat, spacingAfter: CGFloat) {
        ensureSpace(thickness + spacingAfter)
        Palette.accent.setFill()
        UIBezierPath(roundedRect: CGRect(x: margin.left, y: y, width: width, height: thickness), cornerRadius: thickness / 2).fill()
        Palette.leaf.setFill()
        UIBezierPath(roundedRect: CGRect(x: margin.left + width + 7, y: y, width: 34, height: thickness), cornerRadius: thickness / 2).fill()
        y += thickness + spacingAfter
    }

    private func drawMetaBand(_ text: String) {
        let height = max(34, measuredTextHeight(text, font: .systemFont(ofSize: 10.8), width: contentWidth - 24, lineSpacing: 2) + 17)
        ensureSpace(height + 14)
        let rect = CGRect(x: margin.left, y: y, width: contentWidth, height: height)
        Palette.leaf.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 10).fill()
        drawDirectText(
            text,
            rect: rect.insetBy(dx: 12, dy: 8),
            font: .systemFont(ofSize: 10.8, weight: .medium),
            color: Palette.white,
            alignment: .left,
            lineSpacing: 2
        )
        y += height + 14
    }

    private func drawFooter() {
        let y = Self.pageRect.height - 31
        Palette.hairline.setStroke()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin.left, y: y - 12))
        path.addLine(to: CGPoint(x: Self.pageRect.width - margin.right, y: y - 12))
        path.lineWidth = 0.5
        path.stroke()

        drawDirectText(
            "RecipeClipper",
            rect: CGRect(x: margin.left, y: y, width: 180, height: 13),
            font: .systemFont(ofSize: 8.5, weight: .medium),
            color: Palette.mutedInk,
            alignment: .left
        )
        drawDirectText(
            "\(pageNumber)",
            rect: CGRect(x: Self.pageRect.width - margin.right - 60, y: y, width: 60, height: 13),
            font: .systemFont(ofSize: 8.5, weight: .medium),
            color: Palette.mutedInk,
            alignment: .right
        )
    }

    private func drawCookLogs(_ logs: [CookLogPDFSnapshot]) {
        guard !logs.isEmpty else { return }
        ensureSpace(76)
        drawSectionTitle("作った記録", compact: false)

        for log in logs {
            ensureSpace(100)
            drawHairline()
            drawImage(log.imageData, maxHeight: 78, maxWidth: 112, spacingAfter: 5)

            var lines: [String] = [Self.displayDate(log.cookedDate)]
            if let rating = log.rating {
                lines[0] += " \(Self.ratingText(rating))"
            }
            if !log.memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("メモ: \(log.memo)")
            }
            if !log.arrangement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("アレンジ: \(log.arrangement)")
            }
            if !log.nextImprovement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("次回改善: \(log.nextImprovement)")
            }
            drawText(lines.joined(separator: "\n"), font: .systemFont(ofSize: 11), color: Palette.ink, lineSpacing: 2.4, spacingAfter: 10)
        }
    }

    private func drawImage(_ imageData: Data?, maxHeight: CGFloat, maxWidth: CGFloat? = nil, spacingAfter: CGFloat) {
        guard let imageData, let image = UIImage(data: imageData), image.size.width > 0, image.size.height > 0 else { return }
        let widthLimit = min(maxWidth ?? contentWidth, contentWidth)
        let scale = min(widthLimit / image.size.width, maxHeight / image.size.height, 1)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        ensureSpace(drawSize.height + spacingAfter)
        let rect = CGRect(x: margin.left, y: y, width: drawSize.width, height: drawSize.height)
        drawRoundedImage(image, in: rect, cornerRadius: 12)
        y += drawSize.height + spacingAfter
    }

    private func drawRoundedImage(_ image: UIImage, in rect: CGRect, cornerRadius: CGFloat) {
        let cgContext = context.cgContext
        cgContext.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).addClip()
        image.draw(in: rect)
        cgContext.restoreGState()

        Palette.hairline.setStroke()
        let border = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
        border.lineWidth = 0.6
        border.stroke()
    }

    private func drawHairline() {
        ensureSpace(10)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin.left, y: y))
        path.addLine(to: CGPoint(x: margin.left + contentWidth, y: y))
        Palette.hairline.setStroke()
        path.lineWidth = 0.5
        path.stroke()
        y += 9
    }

    private func drawLinkedText(_ text: String, url: URL) {
        let rect = drawText(
            text,
            font: .systemFont(ofSize: 11),
            color: Palette.link,
            lineSpacing: 2,
            spacingAfter: 10
        )
        if let rect {
            context.setURL(url, for: rect)
        }
    }

    @discardableResult
    private func drawText(
        _ text: String,
        font: UIFont,
        color: UIColor,
        lineSpacing: CGFloat = 2,
        spacingAfter: CGFloat = 8,
        maxWidth: CGFloat? = nil
    ) -> CGRect? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = lineSpacing
        let attributedText = NSAttributedString(
            string: trimmed,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]
        )

        return drawAttributedText(attributedText, spacingAfter: spacingAfter, maxWidth: maxWidth ?? contentWidth)
    }

    @discardableResult
    private func drawAttributedText(_ attributedText: NSAttributedString, spacingAfter: CGFloat, maxWidth: CGFloat) -> CGRect? {
        var startIndex = 0
        var unionRect: CGRect?

        while startIndex < attributedText.length {
            var availableHeight = Self.pageRect.height - margin.bottom - y
            if availableHeight < 36 {
                beginPage()
                availableHeight = Self.pageRect.height - margin.bottom - y
            }

            let remainingLength = attributedText.length - startIndex
            let visibleLength = fittingLength(
                in: attributedText,
                startIndex: startIndex,
                maxLength: remainingLength,
                availableHeight: availableHeight,
                maxWidth: maxWidth
            )
            guard visibleLength > 0 else {
                beginPage()
                continue
            }

            let chunk = attributedText.attributedSubstring(from: NSRange(location: startIndex, length: visibleLength))
            let usedHeight = min(measuredHeight(chunk, width: maxWidth), availableHeight)
            let drawRect = CGRect(x: margin.left, y: y, width: maxWidth, height: usedHeight)
            chunk.draw(
                with: drawRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            unionRect = unionRect.map { $0.union(drawRect) } ?? drawRect
            startIndex += visibleLength

            if startIndex < attributedText.length {
                beginPage()
            } else {
                y += usedHeight + spacingAfter
            }
        }

        return unionRect
    }

    private func fittingLength(
        in attributedText: NSAttributedString,
        startIndex: Int,
        maxLength: Int,
        availableHeight: CGFloat,
        maxWidth: CGFloat
    ) -> Int {
        if measuredHeight(attributedText.attributedSubstring(from: NSRange(location: startIndex, length: maxLength)), width: maxWidth) <= availableHeight {
            return maxLength
        }

        var low = 1
        var high = maxLength
        var best = 0
        while low <= high {
            let mid = (low + high) / 2
            let range = NSRange(location: startIndex, length: mid)
            let height = measuredHeight(attributedText.attributedSubstring(from: range), width: maxWidth)
            if height <= availableHeight {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        guard best > 0 else { return 0 }
        return preferredBreakLength(in: attributedText.string as NSString, startIndex: startIndex, proposedLength: best)
    }

    private func preferredBreakLength(in string: NSString, startIndex: Int, proposedLength: Int) -> Int {
        guard proposedLength > 12 else { return proposedLength }
        let end = startIndex + proposedLength
        let searchStart = startIndex + max(1, Int(Double(proposedLength) * 0.72))
        guard searchStart < end else { return proposedLength }

        var index = end - 1
        while index >= searchStart {
            let character = string.character(at: index)
            if character == 10 || character == 13 || character == 32 || character == 12288 {
                return max(1, index - startIndex + 1)
            }
            index -= 1
        }
        return proposedLength
    }

    private func measuredHeight(_ attributedText: NSAttributedString, width: CGFloat) -> CGFloat {
        ceil(attributedText.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).height)
    }

    private func ensureSpace(_ neededHeight: CGFloat) {
        if y + neededHeight > Self.pageRect.height - margin.bottom {
            beginPage()
        }
    }

    private func measuredTextHeight(_ text: String, font: UIFont, width: CGFloat, lineSpacing: CGFloat) -> CGFloat {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = lineSpacing
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle
            ]
        )
        return ceil(attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).height)
    }

    private func drawDirectText(
        _ text: String,
        rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment,
        lineSpacing: CGFloat = 1.5
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = lineSpacing
        NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]
        ).draw(in: rect)
    }

    private func metadataText(for snapshot: RecipePDFSnapshot) -> String {
        var parts: [String] = []
        if let sourceName = snapshot.sourceName {
            parts.append(sourceName)
        } else if let sourceType = snapshot.sourceType {
            parts.append(sourceType)
        }
        if let sourceType = snapshot.sourceType, sourceType != snapshot.sourceName {
            parts.append(sourceType)
        }
        if let rating = snapshot.rating {
            parts.append(Self.ratingText(rating))
        }
        if snapshot.isFavorite {
            parts.append("お気に入り")
        }
        if snapshot.wantsToCookAgain {
            parts.append("また作りたい")
        }
        parts.append("\(snapshot.cookedCount)回作成")
        if let lastCookedDate = snapshot.lastCookedDate {
            parts.append("最終: \(Self.displayDate(lastCookedDate))")
        }
        return parts.joined(separator: " ・ ")
    }

    private static func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }

    private static func ratingText(_ rating: Int) -> String {
        let clamped = min(max(rating, 0), 5)
        return String(repeating: "★", count: clamped) + String(repeating: "☆", count: 5 - clamped)
    }

    private static func loadAppIcon() -> UIImage? {
        let namedCandidates = [
            "recipe-clipping-app-icon",
            "AppIcon",
            "AppIcon60x60",
            "AppIcon76x76"
        ]
        for name in namedCandidates {
            if let image = UIImage(named: name) {
                return image
            }
        }

        guard
            let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
            let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String]
        else {
            return nil
        }

        for name in iconFiles.reversed() {
            if let image = UIImage(named: name) {
                return image
            }
        }
        return nil
    }
}
