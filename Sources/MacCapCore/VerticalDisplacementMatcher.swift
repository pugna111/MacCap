public struct VerticalMatchConfiguration: Equatable, Sendable {
    /// Smallest allowed downward scroll, in pixels.
    public var minimumDisplacement: Int
    /// Largest allowed downward scroll. Nil searches every displacement that
    /// leaves at least `minimumOverlapRows` rows.
    public var maximumDisplacement: Int?
    /// Minimum compared overlap remaining after the ignored top region.
    public var minimumOverlapRows: Int
    public var horizontalSampleStride: Int
    public var verticalSampleStride: Int
    /// Ignores scroll bars and fixed side chrome. Must be in 0..<0.5.
    public var ignoredHorizontalEdgeFraction: Double
    /// Ignores a fixed header at the top of the current frame. Must be in 0..<1.
    public var ignoredTopFraction: Double
    /// Sampling is automatically thinned so each displacement costs roughly
    /// this many grayscale comparisons at most.
    public var targetSampleCountPerCandidate: Int
    /// Rejects pages where another meaningfully different displacement scores
    /// almost as well as the best one (for example, repeating list rows).
    public var minimumDistinctDisplacement: Int
    public var minimumAbsoluteErrorSeparation: Double
    public var minimumRelativeErrorSeparation: Double
    /// A value from 0 through 1. Exact pixel agreement has confidence 1.
    public var minimumConfidence: Double

    public init(
        minimumDisplacement: Int = 1,
        maximumDisplacement: Int? = nil,
        minimumOverlapRows: Int = 48,
        horizontalSampleStride: Int = 4,
        verticalSampleStride: Int = 2,
        ignoredHorizontalEdgeFraction: Double = 0.08,
        ignoredTopFraction: Double = 0.10,
        targetSampleCountPerCandidate: Int = 2_048,
        minimumDistinctDisplacement: Int = 3,
        minimumAbsoluteErrorSeparation: Double = 2,
        minimumRelativeErrorSeparation: Double = 0.15,
        minimumConfidence: Double = 0.94
    ) {
        self.minimumDisplacement = minimumDisplacement
        self.maximumDisplacement = maximumDisplacement
        self.minimumOverlapRows = minimumOverlapRows
        self.horizontalSampleStride = horizontalSampleStride
        self.verticalSampleStride = verticalSampleStride
        self.ignoredHorizontalEdgeFraction = ignoredHorizontalEdgeFraction
        self.ignoredTopFraction = ignoredTopFraction
        self.targetSampleCountPerCandidate = targetSampleCountPerCandidate
        self.minimumDistinctDisplacement = minimumDistinctDisplacement
        self.minimumAbsoluteErrorSeparation = minimumAbsoluteErrorSeparation
        self.minimumRelativeErrorSeparation = minimumRelativeErrorSeparation
        self.minimumConfidence = minimumConfidence
    }
}

public struct VerticalMatch: Equatable, Sendable {
    /// The number of new rows exposed at the bottom of the current frame.
    public let displacement: Int
    public let overlapRows: Int
    public let meanAbsoluteError: Double
    public let confidence: Double
    public let comparedSampleCount: Int

    public init(
        displacement: Int,
        overlapRows: Int,
        meanAbsoluteError: Double,
        confidence: Double,
        comparedSampleCount: Int
    ) {
        self.displacement = displacement
        self.overlapRows = overlapRows
        self.meanAbsoluteError = meanAbsoluteError
        self.confidence = confidence
        self.comparedSampleCount = comparedSampleCount
    }
}

public enum VerticalMatchError: Error, Equatable, Sendable {
    case invalidConfiguration
    case dimensionMismatch(
        previousWidth: Int,
        previousHeight: Int,
        currentWidth: Int,
        currentHeight: Int
    )
    case noCandidateDisplacement
    case lowConfidence(best: Double, required: Double)
    case ambiguousMatch(best: Double, competing: Double)
}

public struct VerticalDisplacementMatcher: Sendable {
    public var configuration: VerticalMatchConfiguration

    public init(configuration: VerticalMatchConfiguration = .init()) {
        self.configuration = configuration
    }

    /// Finds `d` such that `previous[d..<height]` best matches
    /// `current[0..<(height-d)]`.
    public func match(previous: GrayImage, current: GrayImage) throws -> VerticalMatch {
        try validate(configuration)
        guard previous.width == current.width, previous.height == current.height else {
            throw VerticalMatchError.dimensionMismatch(
                previousWidth: previous.width,
                previousHeight: previous.height,
                currentWidth: current.width,
                currentHeight: current.height
            )
        }

        let ignoredTopRows = Int(Double(previous.height) * configuration.ignoredTopFraction)
        let availableMaximum = previous.height
            - ignoredTopRows
            - configuration.minimumOverlapRows
        let requestedMaximum = configuration.maximumDisplacement ?? availableMaximum
        let maximumDisplacement = min(requestedMaximum, availableMaximum)
        guard configuration.minimumDisplacement <= maximumDisplacement else {
            throw VerticalMatchError.noCandidateDisplacement
        }

        var best: VerticalMatch?
        var evaluated: [VerticalMatch] = []
        for displacement in configuration.minimumDisplacement...maximumDisplacement {
            if displacement.isMultiple(of: 64) {
                try Task.checkCancellation()
            }
            let candidate = score(
                previous: previous,
                current: current,
                displacement: displacement,
                ignoredTopRows: ignoredTopRows
            )
            evaluated.append(candidate)
            if best == nil || candidate.meanAbsoluteError < best!.meanAbsoluteError {
                best = candidate
            }
        }

        guard let best else {
            throw VerticalMatchError.noCandidateDisplacement
        }
        guard best.confidence >= configuration.minimumConfidence else {
            throw VerticalMatchError.lowConfidence(
                best: best.confidence,
                required: configuration.minimumConfidence
            )
        }
        if let competing = evaluated
            .filter({ abs($0.displacement - best.displacement)
                >= configuration.minimumDistinctDisplacement })
            .min(by: { $0.meanAbsoluteError < $1.meanAbsoluteError }) {
            let requiredSeparation = max(
                configuration.minimumAbsoluteErrorSeparation,
                best.meanAbsoluteError * configuration.minimumRelativeErrorSeparation
            )
            guard competing.meanAbsoluteError - best.meanAbsoluteError
                    >= requiredSeparation else {
                throw VerticalMatchError.ambiguousMatch(
                    best: best.confidence,
                    competing: competing.confidence
                )
            }
        }
        return best
    }

    public func match(previous: RGBAImage, current: RGBAImage) throws -> VerticalMatch {
        try match(previous: previous.grayscale(), current: current.grayscale())
    }

    private func validate(_ configuration: VerticalMatchConfiguration) throws {
        guard configuration.minimumDisplacement >= 1,
              configuration.maximumDisplacement.map({ $0 >= configuration.minimumDisplacement }) ?? true,
              configuration.minimumOverlapRows >= 1,
              configuration.horizontalSampleStride >= 1,
              configuration.verticalSampleStride >= 1,
              configuration.ignoredHorizontalEdgeFraction.isFinite,
              (0..<0.5).contains(configuration.ignoredHorizontalEdgeFraction),
              configuration.ignoredTopFraction.isFinite,
              (0..<1).contains(configuration.ignoredTopFraction),
              configuration.targetSampleCountPerCandidate >= 1,
              configuration.minimumDistinctDisplacement >= 1,
              configuration.minimumAbsoluteErrorSeparation.isFinite,
              configuration.minimumAbsoluteErrorSeparation >= 0,
              configuration.minimumRelativeErrorSeparation.isFinite,
              configuration.minimumRelativeErrorSeparation >= 0,
              configuration.minimumConfidence.isFinite,
              (0...1).contains(configuration.minimumConfidence) else {
            throw VerticalMatchError.invalidConfiguration
        }
    }

    private func score(
        previous: GrayImage,
        current: GrayImage,
        displacement: Int,
        ignoredTopRows: Int
    ) -> VerticalMatch {
        let overlapRows = previous.height - displacement
        let horizontalMargin = Int(
            Double(previous.width) * configuration.ignoredHorizontalEdgeFraction
        )
        let firstX = horizontalMargin
        let endX = previous.width - horizontalMargin
        let sampledWidth = endX - firstX
        let sampledHeight = overlapRows - ignoredTopRows
        let sampleArea = sampledWidth * sampledHeight
        let requestedScale = (
            Double(sampleArea)
                / Double(configuration.targetSampleCountPerCandidate)
                / Double(configuration.horizontalSampleStride)
                / Double(configuration.verticalSampleStride)
        ).squareRoot().rounded(.up)
        let thinningScale = max(
            1,
            Int(requestedScale)
        )
        let horizontalStride = configuration.horizontalSampleStride * thinningScale
        let verticalStride = configuration.verticalSampleStride * thinningScale
        var totalAbsoluteError: Int64 = 0
        var sampleCount = 0

        var overlapY = ignoredTopRows
        while overlapY < overlapRows {
            let previousRowOffset = (overlapY + displacement) * previous.width
            let currentRowOffset = overlapY * current.width
            var x = firstX
            while x < endX {
                let lhs = Int(previous.pixels[previousRowOffset + x])
                let rhs = Int(current.pixels[currentRowOffset + x])
                totalAbsoluteError += Int64(abs(lhs - rhs))
                sampleCount += 1
                x += horizontalStride
            }
            overlapY += verticalStride
        }

        let meanError = Double(totalAbsoluteError) / Double(sampleCount)
        let confidence = max(0, 1 - (meanError / 255))
        return VerticalMatch(
            displacement: displacement,
            overlapRows: overlapRows,
            meanAbsoluteError: meanError,
            confidence: confidence,
            comparedSampleCount: sampleCount
        )
    }
}
