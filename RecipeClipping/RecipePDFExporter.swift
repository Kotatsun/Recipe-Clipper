import Foundation
import UIKit

struct RecipePDFSnapshot {
    let title: String
    let summary: String
    let servings: String
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
            for (index, snapshot) in snapshots.enumerated() {
                drawer.drawRecipePage(snapshot: snapshot, recipeIndex: index + 1, totalRecipes: snapshots.count)
            }
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
            drawer.drawRecipePage(snapshot: snapshot, recipeIndex: nil, totalRecipes: nil)
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
        servings = recipe.servingsText
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

    private struct IndexedLine {
        let index: Int
        let text: String
    }

    private struct MainPageRemainder {
        let ingredients: [IndexedLine]
        let instructions: [IndexedLine]
        let instructionsStartOnContinuation: Bool
        let summaryNeedsContinuation: Bool
        let noteNeedsContinuation: Bool
        let tagsNeedContinuation: Bool

        var isEmpty: Bool {
            ingredients.isEmpty && instructions.isEmpty && !summaryNeedsContinuation && !noteNeedsContinuation && !tagsNeedContinuation
        }
    }

    private enum IngredientLayout {
        case standard
        case expanded(height: CGFloat)
        case fullPage(columns: Int)

        var movesInstructionsToContinuation: Bool {
            switch self {
            case .standard, .expanded: false
            case .fullPage: true
            }
        }
    }

    private enum Palette {
        static let paper = UIColor(red: 0.965, green: 0.952, blue: 0.915, alpha: 1)
        static let card = UIColor(red: 0.995, green: 0.988, blue: 0.965, alpha: 1)
        static let ink = UIColor(red: 0.17, green: 0.165, blue: 0.145, alpha: 1)
        static let mutedInk = UIColor(red: 0.37, green: 0.355, blue: 0.315, alpha: 1)
        static let faintInk = UIColor(red: 0.49, green: 0.475, blue: 0.425, alpha: 1)
        static let line = UIColor(red: 0.58, green: 0.565, blue: 0.505, alpha: 1)
        static let tomato = UIColor(red: 0.63, green: 0.30, blue: 0.23, alpha: 1)
        static let ember = UIColor(red: 0.69, green: 0.43, blue: 0.28, alpha: 1)
        static let basil = UIColor(red: 0.29, green: 0.37, blue: 0.30, alpha: 1)
        static let olive = UIColor(red: 0.39, green: 0.39, blue: 0.33, alpha: 1)
        static let cream = UIColor(red: 0.94, green: 0.91, blue: 0.83, alpha: 1)
        static let mint = UIColor(red: 0.88, green: 0.88, blue: 0.82, alpha: 1)
        static let white = UIColor.white
    }

    private let context: UIGraphicsPDFRendererContext
    private let paperTexture = UIImage(named: "PDFPaperTexture")
    private let pageInset: CGFloat = 34
    private var pageNumber = 0
    private var flowY: CGFloat = 132
    private var continuationTitle = ""
    private var continuationNumber = "RECIPE"
    private var continuationKicker = "NOTES & HISTORY"

    private var contentWidth: CGFloat { Self.pageRect.width - pageInset * 2 }
    private var flowBottom: CGFloat { Self.pageRect.height - 54 }

    init(context: UIGraphicsPDFRendererContext) {
        self.context = context
    }

    func drawCover(recipeCount: Int, exportedAt: Date) {
        beginPage()

        drawText(
            "Recipe",
            in: CGRect(x: 56, y: 48, width: 120, height: 18),
            font: labelFont(size: 10, weight: .semibold),
            color: Palette.ink,
            characterSpacing: 2.4
        )
        drawText(
            "PRIVATE COOKBOOK  /  RECIPECLIPPER",
            in: CGRect(x: 310, y: 51, width: 229, height: 14),
            font: labelFont(size: 7.2, weight: .medium),
            color: Palette.faintInk,
            alignment: .right,
            characterSpacing: 1.15
        )

        drawHorizontalRule(from: 56, to: 539, y: 86, color: Palette.line, width: 0.7)

        drawText(
            "No.",
            in: CGRect(x: 57, y: 139, width: 36, height: 18),
            font: labelFont(size: 8.5, weight: .medium),
            color: Palette.mutedInk,
            characterSpacing: 0.8
        )
        drawText(
            "01",
            in: CGRect(x: 93, y: 111, width: 92, height: 62),
            font: displayNumberFont(size: 45),
            color: Palette.olive,
            characterSpacing: 2
        )

        drawText(
            "MY RECIPE\nCOLLECTION",
            in: CGRect(x: 185, y: 116, width: 350, height: 122),
            font: serifFont(size: 39, weight: .bold),
            color: Palette.ink,
            lineSpacing: 3,
            characterSpacing: 0.8
        )
        Palette.tomato.setFill()
        UIBezierPath(rect: CGRect(x: 185, y: 251, width: 56, height: 2.2)).fill()
        drawHorizontalRule(from: 56, to: 539, y: 285, color: Palette.line, width: 0.65)

        drawText(
            // "大切なレシピを、一枚ずつ。",
            "",
            in: CGRect(x: 57, y: 331, width: 430, height: 34),
            font: serifFont(size: 20, weight: .semibold),
            color: Palette.ink,
            characterSpacing: 0.5
        )
        drawText(
            // "写真、材料、作り方、そして自分だけの記録。\n日々の台所から生まれたレシピを、静かな一冊にまとめました。",
            "",
            in: CGRect(x: 59, y: 384, width: 407, height: 62),
            font: bodyFont(size: 10.5),
            color: Palette.mutedInk,
            lineSpacing: 5
        )

        drawCoverMetric(label: "RECIPES", value: "\(recipeCount)", suffix: "品", x: 59, y: 527, width: 206)
        drawCoverMetric(label: "EXPORTED", value: Self.displayDate(exportedAt), suffix: "", x: 311, y: 527, width: 228)

        drawHorizontalRule(from: 59, to: 539, y: 665, color: Palette.line.withAlphaComponent(0.72), width: 0.5)
        Palette.tomato.setFill()
        UIBezierPath(rect: CGRect(x: 59, y: 703, width: 2.2, height: 17)).fill()
        drawText("RecipeClipper", in: CGRect(x: 71, y: 701, width: 132, height: 20), font: labelFont(size: 10, weight: .semibold), color: Palette.ink, characterSpacing: 0.5)

        drawText(
            "COOKING ARCHIVE  ·  \(Self.displayYear(exportedAt))",
            in: CGRect(x: 286, y: 710, width: 253, height: 14),
            font: labelFont(size: 7.2, weight: .semibold),
            color: Palette.faintInk,
            alignment: .right,
            characterSpacing: 1.4
        )
    }

    func drawRecipePage(snapshot: RecipePDFSnapshot, recipeIndex: Int?, totalRecipes: Int?) {
        continuationTitle = displayTitle(snapshot.title)
        continuationNumber = recipeNumberText(index: recipeIndex, total: totalRecipes)

        beginPage()
        drawRecipeHeader(snapshot: snapshot, recipeIndex: recipeIndex, totalRecipes: totalRecipes)

        let photoRect = CGRect(x: pageInset, y: 169, width: 248, height: 273)
        let standardIngredientRect = CGRect(x: 300, y: 169, width: 261, height: 273)
        let instructionRect = CGRect(x: pageInset, y: 466, width: contentWidth, height: 298)
        let ingredientLayout = ingredientLayout(for: snapshot, standardRect: standardIngredientRect)

        let ingredientRect: CGRect
        let ingredientColumns: Int
        switch ingredientLayout {
        case .standard:
            ingredientRect = standardIngredientRect
            ingredientColumns = 1
        case let .expanded(height):
            ingredientRect = CGRect(
                x: standardIngredientRect.minX,
                y: standardIngredientRect.minY,
                width: standardIngredientRect.width,
                height: height
            )
            ingredientColumns = 1
        case let .fullPage(columns):
            ingredientRect = CGRect(x: pageInset, y: 169, width: contentWidth, height: 595)
            ingredientColumns = columns
        }

        let noteFits: Bool
        if case .fullPage = ingredientLayout {
            noteFits = snapshot.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            noteFits = drawPhotoCard(snapshot: snapshot, rect: photoRect)
        }
        let ingredientRemainder = drawIngredientCard(snapshot: snapshot, rect: ingredientRect, columns: ingredientColumns)
        let allInstructions = snapshot.instructions.enumerated().map { IndexedLine(index: $0.offset, text: $0.element) }
        let instructionRemainder: [IndexedLine]
        switch ingredientLayout {
        case .standard:
            instructionRemainder = drawInstructionCard(snapshot: snapshot, rect: instructionRect)
        case .expanded:
            let compactInstructionRect = CGRect(x: pageInset, y: 466, width: 248, height: 298)
            var remainingInstructions = drawInstructionCard(
                snapshot: snapshot,
                rect: compactInstructionRect,
                allowsColumns: false
            )
            let secondaryY = ingredientRect.maxY + 18
            let secondaryHeight = instructionRect.maxY - secondaryY
            if !remainingInstructions.isEmpty, secondaryHeight >= 108 {
                let secondaryRect = CGRect(
                    x: standardIngredientRect.minX,
                    y: secondaryY,
                    width: standardIngredientRect.width,
                    height: secondaryHeight
                )
                remainingInstructions = drawInstructionContinuationCard(
                    remainingInstructions,
                    rect: secondaryRect
                )
            }
            instructionRemainder = remainingInstructions
        case .fullPage:
            instructionRemainder = allInstructions
        }
        let summary = snapshot.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let summaryNeedsContinuation = measuredTextHeight(summary, font: .systemFont(ofSize: 8.5), width: 445, lineSpacing: 2) > 32
        let tagsNeedContinuation = snapshot.tags.count > 3 || snapshot.tags.joined(separator: "  #").count > 76

        drawRecipeFooter(snapshot: snapshot)

        let remainder = MainPageRemainder(
            ingredients: ingredientRemainder,
            instructions: instructionRemainder,
            instructionsStartOnContinuation: ingredientLayout.movesInstructionsToContinuation,
            summaryNeedsContinuation: summaryNeedsContinuation,
            noteNeedsContinuation: !noteFits,
            tagsNeedContinuation: tagsNeedContinuation
        )
        if !remainder.isEmpty || !snapshot.cookLogs.isEmpty {
            drawContinuation(snapshot: snapshot, remainder: remainder)
        }
    }

    private func beginPage() {
        context.beginPage()
        pageNumber += 1
        Palette.paper.setFill()
        UIBezierPath(rect: Self.pageRect).fill()
        drawPageTexture()
        drawPageNumber()
    }

    private func drawPageTexture() {
        guard let paperTexture else { return }
        let cg = context.cgContext
        cg.saveGState()
        cg.setAlpha(0.72)
        let scale = max(Self.pageRect.width / paperTexture.size.width, Self.pageRect.height / paperTexture.size.height)
        let size = CGSize(width: paperTexture.size.width * scale, height: paperTexture.size.height * scale)
        paperTexture.draw(in: CGRect(x: Self.pageRect.midX - size.width / 2, y: Self.pageRect.midY - size.height / 2, width: size.width, height: size.height))
        cg.restoreGState()
    }

    private func drawPageNumber() {
        drawText(
            String(format: "%02d", pageNumber),
            in: CGRect(x: Self.pageRect.width - pageInset - 44, y: 811, width: 44, height: 14),
            font: displayNumberFont(size: 9),
            color: Palette.faintInk,
            alignment: .right,
            characterSpacing: 1
        )
    }

    private func drawRecipeHeader(snapshot: RecipePDFSnapshot, recipeIndex: Int?, totalRecipes: Int?) {
        drawText(
            "Recipe",
            in: CGRect(x: pageInset, y: 29, width: 90, height: 15),
            font: labelFont(size: 9, weight: .semibold),
            color: Palette.ink,
            characterSpacing: 2.1
        )
        drawOutlineLabel(
            sourceLabel(snapshot),
            rect: CGRect(x: 434, y: 27, width: 127, height: 21)
        )

        drawText(
            "No.",
            in: CGRect(x: pageInset, y: 79, width: 24, height: 13),
            font: labelFont(size: 7.5, weight: .medium),
            color: Palette.mutedInk
        )
        drawText(
            recipeNumberOnly(index: recipeIndex, total: totalRecipes),
            in: CGRect(x: 59, y: 56, width: 50, height: 44),
            font: displayNumberFont(size: 31),
            color: Palette.olive,
            characterSpacing: 1
        )
        drawTextFitted(
            displayTitle(snapshot.title),
            in: CGRect(x: 119, y: 60, width: 442, height: 41),
            maximumFontSize: 24,
            minimumFontSize: 17,
            fontProvider: { self.serifFont(size: $0, weight: .bold) },
            color: Palette.ink,
            lineSpacing: 1
        )

        let summary = snapshot.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty {
            drawTextFitted(
                summary,
                in: CGRect(x: 119, y: 108, width: 442, height: 32),
                maximumFontSize: 10.2,
                minimumFontSize: 8.3,
                fontProvider: { self.bodyFont(size: $0) },
                color: Palette.mutedInk,
                lineSpacing: 2
            )
        } else {
            drawText(
                metadataText(for: snapshot),
                in: CGRect(x: 119, y: 110, width: 442, height: 22),
                font: bodyFont(size: 9.3, weight: .medium),
                color: Palette.mutedInk
            )
        }

        Palette.line.setStroke()
        let rule = UIBezierPath()
        rule.move(to: CGPoint(x: pageInset, y: 151))
        rule.addLine(to: CGPoint(x: Self.pageRect.width - pageInset, y: 151))
        rule.lineWidth = 0.8
        rule.stroke()
        Palette.olive.setFill()
        UIBezierPath(rect: CGRect(x: pageInset, y: 149.8, width: 63, height: 2.4)).fill()
    }

    @discardableResult
    private func drawPhotoCard(snapshot: RecipePDFSnapshot, rect: CGRect) -> Bool {
        drawCard(rect, fill: Palette.card.withAlphaComponent(0.78))
        let note = snapshot.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasNote = !note.isEmpty
        let imageRect = hasNote
            ? CGRect(x: rect.minX + 9, y: rect.minY + 9, width: rect.width - 18, height: 193)
            : rect.insetBy(dx: 9, dy: 9)
        drawHeroImage(snapshot.imageData, in: imageRect, cornerRadius: 1)
        drawPhotoBadges(snapshot: snapshot, imageRect: imageRect)

        guard hasNote else { return true }
        drawText(
            "KITCHEN NOTE",
            in: CGRect(x: rect.minX + 15, y: rect.minY + 213, width: rect.width - 30, height: 12),
            font: labelFont(size: 7.2, weight: .semibold),
            color: Palette.tomato,
            characterSpacing: 1.6
        )
        let noteRect = CGRect(x: rect.minX + 15, y: rect.minY + 230, width: rect.width - 30, height: 34)
        let font = bodyFont(size: 8.6)
        let fits = measuredTextHeight(note, font: font, width: noteRect.width, lineSpacing: 1.5) <= noteRect.height
        drawText(
            note,
            in: noteRect,
            font: font,
            color: Palette.mutedInk,
            lineSpacing: 1.5,
            lineBreakMode: fits ? .byWordWrapping : .byTruncatingTail
        )
        return fits
    }

    private func drawPhotoBadges(snapshot: RecipePDFSnapshot, imageRect: CGRect) {
        var labels: [String] = []
        if let rating = snapshot.rating { labels.append(Self.ratingText(rating)) }
        if snapshot.isFavorite { labels.append("お気に入り") }
        if snapshot.wantsToCookAgain { labels.append("また作りたい") }
        guard !labels.isEmpty else { return }

        let text = labels.joined(separator: "  ")
        let width = min(imageRect.width - 16, max(58, text.size(withAttributes: [.font: UIFont.systemFont(ofSize: 8.5, weight: .semibold)]).width + 20))
        let badgeRect = CGRect(x: imageRect.minX + 8, y: imageRect.maxY - 29, width: width, height: 21)
        drawPill(text, rect: badgeRect, fill: Palette.ink.withAlphaComponent(0.78), textColor: Palette.white, fontSize: 8.5)
    }

    private func ingredientLayout(for snapshot: RecipePDFSnapshot, standardRect: CGRect) -> IngredientLayout {
        let items = snapshot.ingredients.enumerated().map { IndexedLine(index: $0.offset, text: $0.element) }
        guard !items.isEmpty else { return .standard }

        if drawItems(
            items,
            in: ingredientContentRects(in: standardRect, columns: 1),
            numbered: false,
            fontSize: 8.2,
            shouldDraw: false
        ).isEmpty {
            return .standard
        }

        let maximumHeight: CGFloat = 595
        let minimumIngredientFontSize: CGFloat = 8.2
        let requiredHeight = 84 + itemsHeight(
            items,
            width: standardRect.width - 34,
            numbered: false,
            fontSize: minimumIngredientFontSize
        )
        let expandedHeight = min(maximumHeight, ceil(requiredHeight + 2))
        let expandedRect = CGRect(
            x: standardRect.minX,
            y: standardRect.minY,
            width: standardRect.width,
            height: expandedHeight
        )
        if drawItems(
            items,
            in: ingredientContentRects(in: expandedRect, columns: 1),
            numbered: false,
            fontSize: 8.2,
            shouldDraw: false
        ).isEmpty {
            return .expanded(height: expandedHeight)
        }

        let fullPageRect = CGRect(x: pageInset, y: 169, width: contentWidth, height: maximumHeight)
        for columns in 2...4 {
            if drawItems(
                items,
                in: ingredientContentRects(in: fullPageRect, columns: columns),
                numbered: false,
                fontSize: 6.4,
                shouldDraw: false
            ).isEmpty {
                return .fullPage(columns: columns)
            }
        }
        return .fullPage(columns: 4)
    }

    private func ingredientContentRects(in rect: CGRect, columns: Int) -> [CGRect] {
        let contentY = rect.minY + 68
        let contentHeight = rect.height - 84
        guard columns > 1 else {
            return [CGRect(x: rect.minX + 17, y: contentY, width: rect.width - 34, height: contentHeight)]
        }

        let gap: CGFloat = 18
        let columnWidth = (rect.width - 34 - gap * CGFloat(columns - 1)) / CGFloat(columns)
        return (0..<columns).map { column in
            CGRect(
                x: rect.minX + 17 + CGFloat(column) * (columnWidth + gap),
                y: contentY,
                width: columnWidth,
                height: contentHeight
            )
        }
    }

    private func drawIngredientCard(snapshot: RecipePDFSnapshot, rect: CGRect, columns: Int = 1) -> [IndexedLine] {
        drawCard(rect, fill: Palette.mint.withAlphaComponent(0.46), shadow: false)
        drawSectionHeading(
            title: "材料",
            eyebrow: snapshot.servings.isEmpty ? "INGREDIENTS" : "INGREDIENTS  ·  \(snapshot.servings)",
            rect: CGRect(x: rect.minX + 17, y: rect.minY + 16, width: rect.width - 34, height: 42),
            tint: Palette.basil
        )
        let items = snapshot.ingredients.enumerated().map { IndexedLine(index: $0.offset, text: $0.element) }
        if items.isEmpty {
            drawEmptyState("材料情報なし", rect: CGRect(x: rect.minX + 16, y: rect.minY + 76, width: rect.width - 32, height: 90))
            return []
        }
        let contentRects = ingredientContentRects(in: rect, columns: columns)
        if contentRects.count > 1 {
            Palette.line.withAlphaComponent(0.55).setStroke()
            for index in 0..<(contentRects.count - 1) {
                let dividerX = (contentRects[index].maxX + contentRects[index + 1].minX) / 2
                let divider = UIBezierPath()
                divider.move(to: CGPoint(x: dividerX, y: rect.minY + 68))
                divider.addLine(to: CGPoint(x: dividerX, y: rect.maxY - 18))
                divider.lineWidth = 0.5
                divider.stroke()
            }
        }
        return drawAdaptiveItems(
            items,
            in: contentRects,
            numbered: false,
            maximumFontSize: 10.9,
            minimumFontSize: columns > 1 ? 6.4 : 8.2
        )
    }

    private func drawInstructionCard(
        snapshot: RecipePDFSnapshot,
        rect: CGRect,
        allowsColumns: Bool = true
    ) -> [IndexedLine] {
        drawCard(rect, fill: Palette.card.withAlphaComponent(0.36), shadow: false)
        drawSectionHeading(
            title: "作り方",
            eyebrow: "COOKING INSTRUCTIONS",
            rect: CGRect(x: rect.minX + 20, y: rect.minY + 16, width: rect.width - 40, height: 42),
            tint: Palette.tomato
        )

        let items = snapshot.instructions.enumerated().map { IndexedLine(index: $0.offset, text: $0.element) }
        if items.isEmpty {
            drawEmptyState("作り方情報なし", rect: CGRect(x: rect.minX + 18, y: rect.minY + 78, width: rect.width - 36, height: 120))
            return []
        }

        let contentY = rect.minY + 68
        let contentHeight = rect.height - 84
        let fullWidthContent = CGRect(x: rect.minX + 20, y: contentY, width: rect.width - 40, height: contentHeight)
        if !allowsColumns {
            return drawAdaptiveItems(
                items,
                in: [fullWidthContent],
                numbered: true,
                maximumFontSize: 10.8,
                minimumFontSize: 8.8
            )
        }
        if drawItems(items, in: [fullWidthContent], numbered: true, fontSize: 11.6, shouldDraw: false).isEmpty {
            return drawAdaptiveItems(items, in: [fullWidthContent], numbered: true, maximumFontSize: 11.6, minimumFontSize: 9.8)
        }

        let gap: CGFloat = 22
        let columnWidth = (rect.width - 40 - gap) / 2
        let columns = [
            CGRect(x: rect.minX + 20, y: contentY, width: columnWidth, height: contentHeight),
            CGRect(x: rect.minX + 20 + columnWidth + gap, y: contentY, width: columnWidth, height: contentHeight)
        ]

        Palette.line.withAlphaComponent(0.6).setStroke()
        let divider = UIBezierPath()
        divider.move(to: CGPoint(x: rect.midX, y: contentY))
        divider.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 18))
        divider.lineWidth = 0.5
        divider.stroke()

        return drawAdaptiveItems(items, in: columns, numbered: true, maximumFontSize: 11.5, minimumFontSize: 8.8)
    }

    private func drawInstructionContinuationCard(
        _ items: [IndexedLine],
        rect: CGRect,
        title: String = "作り方（つづき）",
        eyebrow: String = "INSTRUCTIONS CONTINUED"
    ) -> [IndexedLine] {
        drawCard(rect, fill: Palette.card.withAlphaComponent(0.32), shadow: false)
        drawText(
            eyebrow,
            in: CGRect(x: rect.minX + 17, y: rect.minY + 14, width: rect.width - 34, height: 10),
            font: labelFont(size: 6.8, weight: .semibold),
            color: Palette.tomato,
            characterSpacing: 1.25
        )
        drawText(
            title,
            in: CGRect(x: rect.minX + 17, y: rect.minY + 28, width: rect.width - 34, height: 22),
            font: serifFont(size: 13.5, weight: .bold),
            color: Palette.ink
        )
        Palette.tomato.setFill()
        UIBezierPath(rect: CGRect(x: rect.minX + 17, y: rect.minY + 54, width: 34, height: 1.5)).fill()

        let content = CGRect(
            x: rect.minX + 17,
            y: rect.minY + 66,
            width: rect.width - 34,
            height: rect.height - 80
        )
        return drawAdaptiveItems(
            items,
            in: [content],
            numbered: true,
            maximumFontSize: 9.8,
            minimumFontSize: 8.4
        )
    }

    private func drawRecipeFooter(snapshot: RecipePDFSnapshot) {
        let y: CGFloat = 782
        var leftParts: [String] = []
        if !snapshot.tags.isEmpty {
            leftParts.append(snapshot.tags.prefix(3).map { "#\($0)" }.joined(separator: "  "))
        }
        leftParts.append(metadataText(for: snapshot))
        drawText(
            leftParts.filter { !$0.isEmpty }.joined(separator: "   ·   "),
            in: CGRect(x: pageInset, y: y, width: 335, height: 18),
            font: labelFont(size: 7.4, weight: .medium),
            color: Palette.faintInk,
            lineBreakMode: .byTruncatingTail
        )

        if let sourceURL = snapshot.sourceURL {
            let sourceText = snapshot.sourceName ?? sourceURL.host ?? "元レシピ"
            let rect = CGRect(x: 389, y: y, width: 172, height: 18)
            drawText("SOURCE  ↗  \(sourceText)", in: rect, font: labelFont(size: 7.4, weight: .semibold), color: Palette.tomato, alignment: .right, characterSpacing: 0.5, lineBreakMode: .byTruncatingMiddle)
            context.setURL(sourceURL, for: rect)
        }
    }

    private func drawContinuation(snapshot: RecipePDFSnapshot, remainder: MainPageRemainder) {
        if !remainder.ingredients.isEmpty {
            continuationKicker = "INGREDIENTS CONTINUED"
        } else if !remainder.instructions.isEmpty {
            continuationKicker = "COOKING INSTRUCTIONS"
        } else {
            continuationKicker = "NOTES & HISTORY"
        }
        beginContinuationPage()

        if !remainder.ingredients.isEmpty {
            drawFlowHeading(snapshot.servings.isEmpty ? "材料（つづき）" : "材料（\(snapshot.servings)・つづき）", eyebrow: "INGREDIENTS CONTINUED", tint: Palette.basil)
            drawFlowItems(remainder.ingredients, numbered: false)
        }
        if !remainder.instructions.isEmpty {
            drawFlowInstructionCards(
                remainder.instructions,
                startsOnContinuation: remainder.instructionsStartOnContinuation
            )
        }
        continuationKicker = "NOTES & HISTORY"
        if remainder.summaryNeedsContinuation {
            drawFlowHeading("概要", eyebrow: "ABOUT THIS RECIPE", tint: Palette.basil)
            drawFlowText(snapshot.summary, color: Palette.ink)
        }
        if remainder.noteNeedsContinuation {
            drawFlowHeading("自分メモ", eyebrow: "KITCHEN NOTE", tint: Palette.ember)
            drawFlowText(snapshot.note, color: Palette.ink)
        }
        if remainder.tagsNeedContinuation {
            drawFlowHeading("タグ", eyebrow: "TAGS", tint: Palette.basil)
            drawFlowText(snapshot.tags.map { "#\($0)" }.joined(separator: "   "), color: Palette.mutedInk)
        }
        if let sourceURL = snapshot.sourceURL {
            drawFlowHeading("元レシピ", eyebrow: "SOURCE", tint: Palette.tomato)
            let linkRect = drawFlowText(sourceURL.absoluteString, color: Palette.tomato)
            if let linkRect { context.setURL(sourceURL, for: linkRect) }
        }
        drawCookLogsFlow(snapshot.cookLogs)
    }

    private func beginContinuationPage() {
        beginPage()
        drawText("Recipe", in: CGRect(x: pageInset, y: 30, width: 88, height: 14), font: labelFont(size: 8.7, weight: .semibold), color: Palette.ink, characterSpacing: 2)
        drawOutlineLabel(continuationNumber, rect: CGRect(x: 451, y: 28, width: 110, height: 21))
        drawText(
            continuationKicker,
            in: CGRect(x: pageInset, y: 70, width: 176, height: 15),
            font: labelFont(size: 8.2, weight: .semibold),
            color: Palette.tomato,
            characterSpacing: 1.6
        )
        drawTextFitted(
            continuationTitle,
            in: CGRect(x: pageInset, y: 91, width: contentWidth, height: 29),
            maximumFontSize: 20,
            minimumFontSize: 15,
            fontProvider: { self.serifFont(size: $0, weight: .bold) },
            color: Palette.ink
        )
        Palette.line.setStroke()
        let rule = UIBezierPath()
        rule.move(to: CGPoint(x: pageInset, y: 126))
        rule.addLine(to: CGPoint(x: Self.pageRect.width - pageInset, y: 126))
        rule.lineWidth = 0.7
        rule.stroke()
        flowY = 148
    }

    private func drawFlowHeading(_ title: String, eyebrow: String, tint: UIColor) {
        ensureFlowSpace(52)
        drawText(eyebrow, in: CGRect(x: pageInset, y: flowY, width: contentWidth, height: 11), font: labelFont(size: 7.2, weight: .semibold), color: tint, characterSpacing: 1.4)
        drawText(title, in: CGRect(x: pageInset, y: flowY + 15, width: contentWidth, height: 25), font: serifFont(size: 16, weight: .bold), color: Palette.ink)
        flowY += 48
    }

    private func drawFlowItems(_ items: [IndexedLine], numbered: Bool) {
        let maximumItemHeight = flowBottom - 148
        for item in items {
            let height = itemsHeight([item], width: contentWidth, numbered: numbered, fontSize: 11)
            if height > maximumItemHeight {
                let prefix = numbered ? "\(item.index + 1). " : "• "
                drawFlowText(prefix + item.text, color: Palette.ink)
                continue
            }
            ensureFlowSpace(height + 4)
            let rect = CGRect(x: pageInset, y: flowY, width: contentWidth, height: height + 1)
            _ = drawItems([item], in: [rect], numbered: numbered, fontSize: 11, shouldDraw: true)
            flowY += height
        }
        flowY += 14
    }

    private func drawFlowInstructionCards(
        _ items: [IndexedLine],
        startsOnContinuation: Bool
    ) {
        var remaining = items
        var isFirstCard = true

        while !remaining.isEmpty {
            if flowBottom - flowY < 160 {
                beginContinuationPage()
            }

            let availableHeight = flowBottom - flowY
            let desiredHeight = 80 + itemsHeight(
                remaining,
                width: contentWidth - 34,
                numbered: true,
                fontSize: 9.8
            )
            let cardHeight = min(availableHeight, max(160, ceil(desiredHeight + 2)))
            let cardRect = CGRect(x: pageInset, y: flowY, width: contentWidth, height: cardHeight)
            let title = startsOnContinuation && isFirstCard ? "作り方" : "作り方（つづき）"
            let eyebrow = startsOnContinuation && isFirstCard ? "COOKING INSTRUCTIONS" : "INSTRUCTIONS CONTINUED"

            let nextRemainder = drawInstructionContinuationCard(
                remaining,
                rect: cardRect,
                title: title,
                eyebrow: eyebrow
            )
            flowY = cardRect.maxY + 14

            guard nextRemainder.count < remaining.count else {
                drawFlowItems(remaining, numbered: true)
                return
            }

            remaining = nextRemainder
            isFirstCard = false
            if !remaining.isEmpty {
                beginContinuationPage()
            }
        }
    }

    @discardableResult
    private func drawFlowText(_ text: String, color: UIColor) -> CGRect? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let font = bodyFont(size: 10.6)
        let attributed = attributedText(trimmed, font: font, color: color, lineSpacing: 3)
        var start = 0
        var unionRect: CGRect?

        while start < attributed.length {
            ensureFlowSpace(32)
            let available = flowBottom - flowY
            let visible = fittingLength(in: attributed, startIndex: start, maxLength: attributed.length - start, availableHeight: available, width: contentWidth)
            if visible == 0 {
                beginContinuationPage()
                continue
            }
            let chunk = attributed.attributedSubstring(from: NSRange(location: start, length: visible))
            let height = measuredHeight(chunk, width: contentWidth)
            let rect = CGRect(x: pageInset, y: flowY, width: contentWidth, height: height)
            chunk.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            unionRect = unionRect.map { $0.union(rect) } ?? rect
            flowY += height + 16
            start += visible
            if start < attributed.length { beginContinuationPage() }
        }
        return unionRect
    }

    private func drawCookLogsFlow(_ logs: [CookLogPDFSnapshot]) {
        guard !logs.isEmpty else { return }
        drawFlowHeading("作った記録", eyebrow: "COOKING HISTORY  ·  \(logs.count) RECORDS", tint: Palette.ember)

        for (index, log) in logs.enumerated() {
            var lines: [String] = []
            if !log.memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lines.append(log.memo) }
            if !log.arrangement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lines.append("アレンジ: \(log.arrangement)") }
            if !log.nextImprovement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lines.append("次回: \(log.nextImprovement)") }
            let body = lines.isEmpty ? "記録メモなし" : lines.joined(separator: "\n")
            let imageWidth: CGFloat = log.imageData == nil ? 0 : 82
            let textWidth = contentWidth - 32 - imageWidth - (imageWidth > 0 ? 14 : 0)
            let bodyHeight = measuredTextHeight(body, font: bodyFont(size: 9.6), width: textWidth, lineSpacing: 2.5)
            let cardHeight = max(imageWidth, bodyHeight + 35) + 24
            if cardHeight > flowBottom - 148 {
                ensureFlowSpace(35)
                var dateLine = Self.displayDate(log.cookedDate)
                if let rating = log.rating { dateLine += "   \(Self.ratingText(rating))" }
                drawText(dateLine, in: CGRect(x: pageInset, y: flowY, width: contentWidth, height: 18), font: labelFont(size: 8.7, weight: .semibold), color: Palette.tomato)
                flowY += 24
                drawFlowText(body, color: Palette.ink)
                continue
            }
            ensureFlowSpace(cardHeight + 12)

            let card = CGRect(x: pageInset, y: flowY, width: contentWidth, height: cardHeight)
            drawCard(card, fill: index.isMultiple(of: 2) ? Palette.card : Palette.cream.withAlphaComponent(0.64), shadow: false)
            if let data = log.imageData, let image = UIImage(data: data) {
                drawAspectFill(image, in: CGRect(x: card.minX + 12, y: card.minY + 12, width: 82, height: cardHeight - 24), cornerRadius: 10)
            }
            let textX = card.minX + 16 + imageWidth + (imageWidth > 0 ? 10 : 0)
            var dateLine = Self.displayDate(log.cookedDate)
            if let rating = log.rating { dateLine += "   \(Self.ratingText(rating))" }
            drawText(dateLine, in: CGRect(x: textX, y: card.minY + 14, width: textWidth, height: 16), font: labelFont(size: 8.7, weight: .semibold), color: Palette.tomato)
            drawText(body, in: CGRect(x: textX, y: card.minY + 36, width: textWidth, height: card.height - 48), font: bodyFont(size: 9.6), color: Palette.ink, lineSpacing: 2.5)
            flowY += cardHeight + 12
        }
    }

    private func drawAdaptiveItems(
        _ items: [IndexedLine],
        in rects: [CGRect],
        numbered: Bool,
        maximumFontSize: CGFloat,
        minimumFontSize: CGFloat
    ) -> [IndexedLine] {
        var selectedSize = minimumFontSize
        var size = maximumFontSize
        while size >= minimumFontSize {
            if drawItems(items, in: rects, numbered: numbered, fontSize: size, shouldDraw: false).isEmpty {
                selectedSize = size
                break
            }
            size -= 0.4
        }
        return drawItems(items, in: rects, numbered: numbered, fontSize: selectedSize, shouldDraw: true)
    }

    private func drawItems(
        _ items: [IndexedLine],
        in rects: [CGRect],
        numbered: Bool,
        fontSize: CGFloat,
        shouldDraw: Bool
    ) -> [IndexedLine] {
        guard !rects.isEmpty else { return items }
        let bodyFont = bodyFont(size: fontSize)
        var itemIndex = 0
        var columnIndex = 0
        var cursorY = rects[0].minY

        while itemIndex < items.count && columnIndex < rects.count {
            let column = rects[columnIndex]
            let markerWidth: CGFloat = numbered ? 27 : 13
            let textWidth = column.width - markerWidth
            let item = items[itemIndex]
            let textHeight = measuredTextHeight(item.text, font: bodyFont, width: textWidth, lineSpacing: numbered ? 2.6 : 1.8)
            let height = max(numbered ? 22 : 13, textHeight) + (numbered ? 11 : 7)

            if cursorY + height > column.maxY + 0.5 {
                columnIndex += 1
                if columnIndex < rects.count { cursorY = rects[columnIndex].minY }
                continue
            }

            if shouldDraw {
                if numbered {
                    let circleRect = CGRect(x: column.minX + 1, y: cursorY + 1, width: 18, height: 18)
                    Palette.olive.setFill()
                    UIBezierPath(ovalIn: circleRect).fill()
                    drawText("\(item.index + 1)", in: circleRect.offsetBy(dx: 0, dy: 2.7), font: labelFont(size: 7.5, weight: .semibold), color: Palette.white, alignment: .center)
                } else {
                    Palette.olive.setFill()
                    UIBezierPath(ovalIn: CGRect(x: column.minX + 1, y: cursorY + 5, width: 3.5, height: 3.5)).fill()
                }
                drawText(
                    item.text,
                    in: CGRect(x: column.minX + markerWidth, y: cursorY, width: textWidth, height: textHeight + 2),
                    font: bodyFont,
                    color: Palette.ink,
                    lineSpacing: numbered ? 2.6 : 1.8
                )
                if !numbered {
                    Palette.line.withAlphaComponent(0.72).setStroke()
                    let line = UIBezierPath()
                    line.move(to: CGPoint(x: column.minX + markerWidth, y: cursorY + height - 3))
                    line.addLine(to: CGPoint(x: column.maxX, y: cursorY + height - 3))
                    line.setLineDash([1.1, 2.2], count: 2, phase: 0)
                    line.lineWidth = 0.55
                    line.stroke()
                }
            }
            cursorY += height
            itemIndex += 1
        }
        return Array(items.dropFirst(itemIndex))
    }

    private func itemsHeight(_ items: [IndexedLine], width: CGFloat, numbered: Bool, fontSize: CGFloat) -> CGFloat {
        let markerWidth: CGFloat = numbered ? 27 : 13
        let font = bodyFont(size: fontSize)
        return items.reduce(CGFloat.zero) { result, item in
            let textHeight = measuredTextHeight(item.text, font: font, width: width - markerWidth, lineSpacing: numbered ? 2.6 : 1.8)
            return result + max(numbered ? 22 : 13, textHeight) + (numbered ? 11 : 7)
        }
    }

    private func drawSectionHeading(title: String, eyebrow: String, rect: CGRect, tint: UIColor) {
        drawText(eyebrow, in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 10), font: labelFont(size: 7.1, weight: .semibold), color: tint, characterSpacing: 1.5)
        drawText(title, in: CGRect(x: rect.minX, y: rect.minY + 14, width: rect.width, height: 25), font: serifFont(size: 16, weight: .bold), color: Palette.ink, characterSpacing: 0.8)
        tint.setFill()
        UIBezierPath(rect: CGRect(x: rect.minX, y: rect.maxY - 1, width: 40, height: 1.8)).fill()
    }

    private func drawEmptyState(_ text: String, rect: CGRect) {
        drawText("—  \(text)", in: rect, font: bodyFont(size: 9.8, weight: .medium), color: Palette.faintInk, alignment: .center)
    }

    private func drawCard(_ rect: CGRect, fill: UIColor, shadow: Bool = true) {
        let cg = context.cgContext
        cg.saveGState()
        if shadow { cg.setShadow(offset: CGSize(width: 0, height: 2), blur: 7, color: UIColor.black.withAlphaComponent(0.09).cgColor) }
        fill.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 6).fill()
        cg.restoreGState()
        Palette.line.withAlphaComponent(0.48).setStroke()
        let border = UIBezierPath(roundedRect: rect, cornerRadius: 6)
        border.lineWidth = 0.4
        border.stroke()
    }

    private func drawHeroImage(_ data: Data?, in rect: CGRect, cornerRadius: CGFloat) {
        if let data, let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 {
            drawAspectFill(image, in: rect, cornerRadius: cornerRadius)
            return
        }
        Palette.cream.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).fill()
        Palette.tomato.withAlphaComponent(0.12).setFill()
        UIBezierPath(ovalIn: CGRect(x: rect.midX - 46, y: rect.midY - 46, width: 92, height: 92)).fill()
        if let icon = UIImage(systemName: "fork.knife")?.withTintColor(Palette.tomato, renderingMode: .alwaysOriginal) {
            icon.draw(in: CGRect(x: rect.midX - 21, y: rect.midY - 21, width: 42, height: 42))
        }
    }

    private func drawAspectFill(_ image: UIImage, in rect: CGRect, cornerRadius: CGFloat) {
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let drawRect = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        let cg = context.cgContext
        cg.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).addClip()
        image.draw(in: drawRect)
        cg.restoreGState()
    }

    private func drawPill(_ text: String, rect: CGRect, fill: UIColor, textColor: UIColor, fontSize: CGFloat = 8.5) {
        fill.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 4).fill()
        drawText(text, in: rect.insetBy(dx: 8, dy: 5), font: labelFont(size: fontSize, weight: .semibold), color: textColor, alignment: .center, lineBreakMode: .byTruncatingMiddle)
    }

    private func drawOutlineLabel(_ text: String, rect: CGRect) {
        Palette.olive.withAlphaComponent(0.82).setStroke()
        let border = UIBezierPath(roundedRect: rect, cornerRadius: 3)
        border.lineWidth = 0.55
        border.stroke()
        drawText(text, in: rect.insetBy(dx: 8, dy: 5), font: labelFont(size: 7.2, weight: .semibold), color: Palette.olive, alignment: .center, characterSpacing: 0.9, lineBreakMode: .byTruncatingMiddle)
    }

    private func drawHorizontalRule(from startX: CGFloat, to endX: CGFloat, y: CGFloat, color: UIColor, width: CGFloat) {
        color.setStroke()
        let line = UIBezierPath()
        line.move(to: CGPoint(x: startX, y: y))
        line.addLine(to: CGPoint(x: endX, y: y))
        line.lineWidth = width
        line.stroke()
    }

    private func drawCoverMetric(label: String, value: String, suffix: String, x: CGFloat, y: CGFloat, width: CGFloat) {
        drawHorizontalRule(from: x, to: x + width, y: y, color: Palette.line, width: 0.55)
        drawText(label, in: CGRect(x: x, y: y + 15, width: width, height: 12), font: labelFont(size: 7.5, weight: .semibold), color: Palette.faintInk, characterSpacing: 1.6)
        drawTextFitted(value, in: CGRect(x: x, y: y + 39, width: width - 36, height: 36), maximumFontSize: 25, minimumFontSize: 16, fontProvider: { self.displayNumberFont(size: $0) }, color: Palette.ink)
        if !suffix.isEmpty {
            drawText(suffix, in: CGRect(x: x + width - 34, y: y + 53, width: 30, height: 16), font: bodyFont(size: 9, weight: .medium), color: Palette.mutedInk, alignment: .right)
        }
    }

    private func ensureFlowSpace(_ height: CGFloat) {
        if flowY + height > flowBottom { beginContinuationPage() }
    }

    private func drawTextFitted(
        _ text: String,
        in rect: CGRect,
        maximumFontSize: CGFloat,
        minimumFontSize: CGFloat,
        fontProvider: (CGFloat) -> UIFont,
        color: UIColor,
        lineSpacing: CGFloat = 0
    ) {
        var size = maximumFontSize
        while size > minimumFontSize {
            let font = fontProvider(size)
            if measuredTextHeight(text, font: font, width: rect.width, lineSpacing: lineSpacing) <= rect.height { break }
            size -= 0.5
        }
        drawText(text, in: rect, font: fontProvider(max(size, minimumFontSize)), color: color, lineSpacing: lineSpacing, lineBreakMode: .byTruncatingTail)
    }

    private func drawText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .left,
        lineSpacing: CGFloat = 0,
        characterSpacing: CGFloat = 0,
        lineBreakMode: NSLineBreakMode = .byWordWrapping
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineSpacing = lineSpacing
        style.lineBreakMode = lineBreakMode
        NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: style,
                .kern: characterSpacing
            ]
        ).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }

    private func attributedText(_ text: String, font: UIFont, color: UIColor, lineSpacing: CGFloat) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = lineSpacing
        return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }

    private func measuredTextHeight(_ text: String, font: UIFont, width: CGFloat, lineSpacing: CGFloat) -> CGFloat {
        measuredHeight(attributedText(text, font: font, color: Palette.ink, lineSpacing: lineSpacing), width: width)
    }

    private func measuredHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        ceil(text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
    }

    private func fittingLength(in text: NSAttributedString, startIndex: Int, maxLength: Int, availableHeight: CGFloat, width: CGFloat) -> Int {
        let whole = text.attributedSubstring(from: NSRange(location: startIndex, length: maxLength))
        if measuredHeight(whole, width: width) <= availableHeight { return maxLength }
        var low = 1
        var high = maxLength
        var best = 0
        while low <= high {
            let middle = (low + high) / 2
            let candidate = text.attributedSubstring(from: NSRange(location: startIndex, length: middle))
            if measuredHeight(candidate, width: width) <= availableHeight {
                best = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        guard best > 0 else { return 0 }
        return preferredBreakLength(in: text.string as NSString, startIndex: startIndex, proposedLength: best)
    }

    private func preferredBreakLength(in text: NSString, startIndex: Int, proposedLength: Int) -> Int {
        guard proposedLength > 12 else { return proposedLength }
        let end = startIndex + proposedLength
        let searchStart = startIndex + max(1, Int(Double(proposedLength) * 0.72))
        var cursor = end - 1
        while cursor >= searchStart {
            let value = text.character(at: cursor)
            if value == 10 || value == 13 || value == 32 || value == 12288 || value == 12290 {
                return max(1, cursor - startIndex + 1)
            }
            cursor -= 1
        }
        return proposedLength
    }

    private func serifFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let hiraginoName = weight.rawValue >= UIFont.Weight.semibold.rawValue ? "HiraMinProN-W6" : "HiraMinProN-W3"
        if let font = UIFont(name: hiraginoName, size: size) {
            return font
        }
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    private func bodyFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let hiraginoName = weight.rawValue >= UIFont.Weight.semibold.rawValue
            ? "HiraginoSans-W6"
            : weight.rawValue >= UIFont.Weight.medium.rawValue ? "HiraginoSans-W4" : "HiraginoSans-W3"
        return UIFont(name: hiraginoName, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    private func labelFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        UIFont(name: weight.rawValue >= UIFont.Weight.semibold.rawValue ? "AvenirNext-DemiBold" : "AvenirNext-Medium", size: size)
            ?? .systemFont(ofSize: size, weight: weight)
    }

    private func displayNumberFont(size: CGFloat) -> UIFont {
        UIFont(name: "Didot", size: size) ?? serifFont(size: size, weight: .regular)
    }

    private func displayTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "無題のレシピ" : trimmed
    }

    private func recipeNumberText(index: Int?, total: Int?) -> String {
        guard let index else { return "RECIPE" }
        let width = max(2, String(total ?? index).count)
        return "RECIPE  " + String(format: "%0*d", width, index)
    }

    private func recipeNumberOnly(index: Int?, total: Int?) -> String {
        let index = index ?? 1
        let width = max(2, String(total ?? index).count)
        return String(format: "%0*d", width, index)
    }

    private func sourceLabel(_ snapshot: RecipePDFSnapshot) -> String {
        (snapshot.sourceType ?? snapshot.sourceName ?? "MY RECIPE").uppercased()
    }

    private func metadataText(for snapshot: RecipePDFSnapshot) -> String {
        var parts: [String] = []
        if let rating = snapshot.rating { parts.append(Self.ratingText(rating)) }
        if snapshot.isFavorite { parts.append("お気に入り") }
        if snapshot.wantsToCookAgain { parts.append("また作りたい") }
        if snapshot.cookedCount > 0 { parts.append("\(snapshot.cookedCount)回作成") }
        if let lastCookedDate = snapshot.lastCookedDate { parts.append("最終 \(Self.displayDate(lastCookedDate))") }
        return parts.joined(separator: "  ·  ")
    }

    private static func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }

    private static func displayYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy"
        return formatter.string(from: date)
    }

    private static func ratingText(_ rating: Int) -> String {
        String(repeating: "★", count: min(max(rating, 0), 5))
    }
}
