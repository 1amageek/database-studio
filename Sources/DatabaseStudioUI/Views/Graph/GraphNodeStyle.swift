import SwiftUI

/// ノード種別ごとのスタイル定義
struct GraphNodeStyle {
    let color: Color
    let iconName: String
    let radius: CGFloat

    /// ロールベースのスタイル解決
    static func style(for role: GraphNodeRole) -> GraphNodeStyle {
        switch role {
        case .type:
            return GraphNodeStyle(color: .blue, iconName: "square.stack.3d.up", radius: 30)
        case .instance:
            return GraphNodeStyle(color: .green, iconName: "circle.fill", radius: 26)
        case .property:
            return GraphNodeStyle(color: .orange, iconName: "arrow.right", radius: 22)
        case .literal:
            return GraphNodeStyle(color: .gray, iconName: "quote.closing", radius: 20)
        }
    }

    /// クラスラベルからアイコンを解決
    static func iconName(forClassLabel label: String) -> String? {
        classIcons[label]
    }

    /// ルートクラスラベルから色を解決
    static func color(forClassLabel label: String) -> Color? {
        rootClassColors[label]
    }

    /// ルートクラスかどうか判定（色マッピングに存在）
    static func isPrimitiveClass(_ label: String) -> Bool {
        rootClassColors[label] != nil
    }

    // MARK: - クラス → SF Symbol マッピング
    // ルートクラス + 階層で定義済みのサブクラスすべてにアイコンを設定。
    // ここに無いクラスは BFS で最も近い祖先のアイコンを継承する。

    private static let classIcons: [String: String] = [

        // ═══════════════════════════════════════════════════
        // Activity
        // ═══════════════════════════════════════════════════
        "Activity":                 "figure.run",
        "Campaign":                 "flag.fill",
        "MilitaryCampaign":         "shield.lefthalf.filled",
        "Battle":                   "flame.fill",
        "Siege":                    "shield.slash",
        "PhysicalVerification":     "checkmark.shield.fill",
        "AntennaCheck":             "antenna.radiowaves.left.and.right",
        "DRC":                      "checkmark.shield.fill",
        "LVS":                      "checkmark.shield.fill",
        "MetalDensityCheck":        "checkmark.shield.fill",
        "PEX":                      "checkmark.shield.fill",
        "Program":                  "list.bullet.rectangle",
        "Project":                  "folder.fill",
        "FacilityConstruction":     "hammer.fill",
        "OpenSourceProject":        "chevron.left.forwardslash.chevron.right",
        "RealEstateDevelopmentProject": "building.fill",
        "Research":                 "magnifyingglass",
        "Experiment":               "flask.fill",
        "Survey":                   "doc.text.magnifyingglass",

        // ═══════════════════════════════════════════════════
        // Award
        // ═══════════════════════════════════════════════════
        "Award":                    "trophy.fill",
        "Certification":            "checkmark.seal.fill",
        "CertificationEvent":       "checkmark.seal.fill",
        "HeritageRegistration":     "building.columns",
        "License":                  "checkmark.seal.fill",
        "RecognitionEvent":         "checkmark.seal.fill",
        "Prize":                    "medal.fill",
        "Ranking":                  "list.number",

        // ═══════════════════════════════════════════════════
        // CreativeWork
        // ═══════════════════════════════════════════════════
        "CreativeWork":             "doc.richtext.fill",
        "Artwork":                  "paintbrush.fill",
        "Statue":                   "figure.stand",
        "Media":                    "play.rectangle.fill",
        "CareerSupportMedia":       "play.rectangle.fill",
        "Patent":                   "doc.badge.gearshape",
        "CircuitDiagram":           "cpu",
        "DesignRuleFile":           "doc.fill",
        "LayoutView":               "rectangle.split.3x3",
        "Netlist":                  "point.3.connected.trianglepath.dotted",
        "SymbolLibrary":            "books.vertical.fill",
        "TechnologyFile":           "doc.fill",
        "Publication":              "book.fill",
        "IndustryReport":           "doc.plaintext",
        "Report":                   "doc.plaintext",
        "ResearchPaper":            "doc.text.magnifyingglass",

        // ═══════════════════════════════════════════════════
        // Education
        // ═══════════════════════════════════════════════════
        "Education":                "graduationcap.fill",
        "Curriculum":               "list.bullet",
        "Training":                 "figure.walk",
        "TrainingProgram":          "figure.walk",

        // ═══════════════════════════════════════════════════
        // Event
        // ═══════════════════════════════════════════════════
        "Event":                    "calendar",
        // Agreement
        "Agreement":                "pencil",
        "Acquisition":              "cart.fill",
        "AcquisitionEvent":         "cart.fill",
        "Funding":                  "banknote.fill",
        "FundingEvent":             "banknote.fill",
        "FundingRound":             "banknote.fill",
        "Marriage":                 "heart.fill",
        "MemorandumSigning":        "pencil",
        "Merger":                   "arrow.triangle.merge",
        "Partnership":              "person.2.fill",
        "BusinessCollaboration":    "person.2.fill",
        "PartnershipAnnouncement":  "person.2.fill",
        "PartnershipEvent":         "person.2.fill",
        "ProjectParticipationEvent":"person.2.fill",
        "StrategicPartnership":     "person.2.fill",
        // Announcement
        "Announcement":             "megaphone.fill",
        "BusinessMilestone":        "flag.fill",
        "CorporateEvent":           "building.fill",
        "CompanyRenaming":          "textformat",
        "Relocation":               "arrow.left.arrow.right",
        "StockListing":             "chart.line.uptrend.xyaxis",
        "Disclosure":               "doc.plaintext",
        "FinancialReportEvent":     "doc.plaintext",
        "FinancialResultAnnouncement": "doc.plaintext",
        "FinancialResultsEvent":    "doc.plaintext",
        "Launch":                   "paperplane.fill",
        "Opening":                  "door.left.hand.open",
        "ProductAnnouncement":      "shippingbox.fill",
        "ProductLaunchEvent":       "shippingbox.fill",
        "ServiceLaunchEvent":       "paperplane.fill",
        "PolicyAnnouncement":       "doc.text.fill",
        "ProgramAnnouncementEvent": "megaphone.fill",
        "Release":                  "arrow.up.circle.fill",
        "ModelRelease":             "arrow.up.circle.fill",
        "OpenSourceRelease":        "chevron.left.forwardslash.chevron.right",
        "StatementEvent":           "quote.bubble.fill",
        "TechnologicalAchievement": "star.fill",
        "TechnologyAnnouncement":   "cpu",
        // Election
        "Election":                 "checkmark.rectangle",
        "ElectionEvent":            "checkmark.rectangle",
        // Exhibition
        "Exhibition":               "photo.fill",
        "ArtExhibition":            "paintpalette.fill",
        // Gathering
        "Gathering":                "person.3.fill",
        "Ceremony":                 "sparkles",
        "AnniversaryEvent":         "sparkles",
        "AwardEvent":               "trophy.fill",
        "Competition":              "trophy",
        "Conference":               "person.3.fill",
        "TechEvent":                "desktopcomputer",
        "Festival":                 "theatermasks.fill",
        "FestivalEvent":            "theatermasks.fill",
        "ShareholderMeetingEvent":  "person.3.fill",
        // HistoricalPeriod
        "HistoricalPeriod":         "clock.arrow.circlepath",
        // Incident
        "Incident":                 "exclamationmark.triangle.fill",
        "Accident":                 "exclamationmark.octagon.fill",
        "TrafficAccident":          "car.fill",
        "Crime":                    "lock.fill",
        "CrimeEvent":               "lock.fill",
        "Crisis":                   "bolt.fill",
        "ManufacturingDefect":      "exclamationmark.triangle.fill",
        "NaturalDisaster":          "tornado",
        "WeatherEvent":             "cloud.bolt.fill",
        // LegalAction
        "LegalAction":              "text.magnifyingglass",
        // Transition
        "Transition":               "arrow.triangle.2.circlepath",
        "Appointment":              "person.badge.plus",
        "ExecutiveAppointment":     "person.badge.plus",
        "ExecutiveChangeEvent":     "person.badge.plus",
        "Birth":                    "sparkle",
        "Closure":                  "xmark.square.fill",
        "Death":                    "xmark.circle.fill",
        "Execution":                "xmark.circle.fill",
        "Seppuku":                  "xmark.circle.fill",
        "Suicide":                  "xmark.circle.fill",
        "Founding":                 "plus.circle.fill",
        "Establishment":            "plus.circle.fill",
        "OrganizationFounding":     "plus.circle.fill",
        "Listing":                  "list.bullet.rectangle",
        "Restructuring":            "arrow.triangle.2.circlepath",
        "CorporateRebranding":      "textformat",
        "CorporateRestructuring":   "arrow.triangle.2.circlepath",
        "OfficeRelocation":         "arrow.left.arrow.right",
        "OrganizationalRestructuring": "arrow.triangle.2.circlepath",

        // ═══════════════════════════════════════════════════
        // Facility
        // ═══════════════════════════════════════════════════
        "Facility":                 "building.columns.fill",
        "EducationalFacility":      "book.fill",
        "BotanicalGarden":          "leaf.fill",
        "Factory":                  "hammer.fill",
        "ManufacturingFacility":    "hammer.fill",
        "Infrastructure":           "square.grid.3x3.fill",
        "Castle":                   "building.columns",
        "MixedUseBuilding":         "building.fill",
        "Road":                     "road.lanes",
        "Station":                  "tram.fill",
        "StationGate":              "tram.fill",
        "Tower":                    "building.fill",
        "UndergroundPassage":       "arrow.down.to.line",
        "MedicalFacility":          "cross.case.fill",
        "Office":                   "desktopcomputer",
        "Hotel":                    "bed.double.fill",
        "OfficeLocation":           "desktopcomputer",
        "ReligiousFacility":        "building.fill",
        "BuddhistTemple":           "building.fill",
        "ShintoShrine":             "building.fill",
        "Shrine":                   "building.fill",
        "Temple":                   "building.fill",
        "ResearchFacility":         "flask.fill",

        // ═══════════════════════════════════════════════════
        // GeographicFeature
        // ═══════════════════════════════════════════════════
        "GeographicFeature":        "globe.americas.fill",
        "ArchaeologicalSite":       "building.columns",
        "PalaceSite":               "building.columns",
        "Tumulus":                   "triangle.fill",
        "Forest":                   "tree.fill",

        // ═══════════════════════════════════════════════════
        // Industry
        // ═══════════════════════════════════════════════════
        "Industry":                 "gearshape.2.fill",
        "EnergyIndustry":           "bolt.fill",
        "FinancialIndustry":        "dollarsign.circle.fill",
        "ManufacturingIndustry":    "hammer.fill",
        "ConstructionIndustry":     "hammer.fill",
        "RoboticsIndustry":         "figure.stand",
        "SemiconductorFoundry":     "cpu",
        "ServiceIndustry":          "person.2.fill",
        "TechnologyIndustry":       "desktopcomputer",
        "HRTechField":              "person.crop.circle.fill",
        "SemiconductorIndustry":    "cpu",

        // ═══════════════════════════════════════════════════
        // Market
        // ═══════════════════════════════════════════════════
        "Market":                   "chart.line.uptrend.xyaxis",
        "CommodityMarket":          "shippingbox",
        "FinancialMarket":          "chart.bar.fill",
        "StockExchange":            "chart.bar.fill",
        "StockMarket":              "chart.bar.fill",
        "TechnologyMarket":         "desktopcomputer",

        // ═══════════════════════════════════════════════════
        // Method
        // ═══════════════════════════════════════════════════
        "Method":                   "gearshape.fill",
        "Algorithm":                "function",
        "SimulationModel":          "waveform.path.ecg",
        "SPICEModel":               "waveform.path.ecg",
        "BusinessStrategy":         "target",
        "BusinessModel":            "target",
        "MilitaryTactic":           "shield.lefthalf.filled",
        "SalesApproach":            "target",
        "Strategy":                 "target",
        "Framework":                "square.grid.3x3",
        "ComputationalFramework":   "square.grid.3x3",
        "Process":                  "arrow.triangle.branch",
        "BenchmarkTest":            "speedometer",
        "CircuitSimulation":        "waveform.path.ecg",
        "LayoutDesign":             "rectangle.split.3x3",
        "LogicSynthesis":           "cpu",
        "PlaceAndRoute":            "rectangle.split.3x3",
        "SemiconductorManufacturingProcess": "cpu",
        "TimingVerification":       "clock.fill",

        // ═══════════════════════════════════════════════════
        // Metric
        // ═══════════════════════════════════════════════════
        "Metric":                   "chart.bar.fill",
        "FinancialMetric":          "dollarsign.circle.fill",
        "FinancialResult":          "dollarsign.circle.fill",
        "PerformanceMetric":        "speedometer",
        "Benchmark":                "speedometer",
        "Rating":                   "star.fill",
        "StatisticalMetric":        "number",

        // ═══════════════════════════════════════════════════
        // MilitaryOrganization
        // ═══════════════════════════════════════════════════
        "MilitaryOrganization":     "shield.fill",
        "MilitaryForce":            "shield.fill",

        // ═══════════════════════════════════════════════════
        // Occupation
        // ═══════════════════════════════════════════════════
        "Occupation":               "briefcase.fill",
        "Position":                 "person.crop.square",
        "GuestProfessor":           "graduationcap.fill",
        "Profession":               "wrench.and.screwdriver",

        // ═══════════════════════════════════════════════════
        // Organism
        // ═══════════════════════════════════════════════════
        "Organism":                 "leaf.fill",
        "Animal":                   "pawprint.fill",
        "FishSpecies":              "fish.fill",
        "Human":                    "person.fill",
        "Microorganism":            "circle.dashed",
        "Plant":                    "leaf.fill",

        // ═══════════════════════════════════════════════════
        // Organization
        // ═══════════════════════════════════════════════════
        "Organization":             "building.2.fill",
        "AcademicInstitution":      "graduationcap.fill",
        "ResearchInstitute":        "flask.fill",
        "University":               "graduationcap.fill",
        "Company":                  "building.fill",
        "AICompany":                "cpu",
        "AutomobileCompany":        "car.fill",
        "AutomotiveCompany":        "car.fill",
        "AutomotiveManufacturer":   "car.fill",
        "Bank":                     "creditcard.fill",
        "BusinessDivision":         "rectangle.3.group",
        "BusinessSegment":          "rectangle.3.group",
        "BusinessUnit":             "rectangle.3.group",
        "CloudServiceProvider":     "cloud.fill",
        "ConstructionCompany":      "hammer.fill",
        "HouseManufacturer":        "house.fill",
        "MidSizeGeneralContractor": "hammer.fill",
        "SemiMajorGeneralContractor": "hammer.fill",
        "SuperGeneralContractor":   "hammer.fill",
        "ConsultingFirm":           "person.crop.circle.fill",
        "CreativeAgency":           "paintpalette.fill",
        "DispatchCompany":          "person.2.fill",
        "FAManufacturer":           "gearshape.2.fill",
        "Fabless":                  "cpu",
        "FinancialInstitution":     "banknote.fill",
        "FinancialGroup":           "banknote.fill",
        "InvestmentBank":           "banknote.fill",
        "SecuritiesCompany":        "chart.bar.fill",
        "FinancialServicesCompany": "dollarsign.circle.fill",
        "Foundry":                  "cpu",
        "FoundryCompany":           "cpu",
        "HRTechCompany":            "person.crop.circle.fill",
        "HealthcareDataCompany":    "cross.case.fill",
        "HoldingCompany":           "building.2.fill",
        "IDM":                      "cpu",
        "ITCompany":                "desktopcomputer",
        "InvestmentFirm":           "dollarsign.circle.fill",
        "VentureCapital":           "dollarsign.circle.fill",
        "JointVenture":             "arrow.triangle.merge",
        "PublicCompany":            "chart.line.uptrend.xyaxis",
        "RoboticsCompany":          "figure.stand",
        "SemiconductorCompany":     "cpu",
        "SportsTeam":               "figure.run",
        "Startup":                  "lightbulb.fill",
        "TechnologyCompany":        "desktopcomputer",
        "TelecommunicationsCompany":"antenna.radiowaves.left.and.right",
        "VentureCapitalFirm":       "dollarsign.circle.fill",
        "GovernmentAgency":         "building.2",
        "EducationBoard":           "graduationcap.fill",
        "Regime":                   "crown.fill",
        "WeatherStation":           "cloud.sun.fill",
        "InternationalOrganization":"globe",
        "MediaOrganization":        "newspaper.fill",
        "NonProfitOrganization":    "heart.circle.fill",
        "AnniversaryAssociation":   "heart.circle.fill",
        "IndustryAssociation":      "gearshape.2.fill",
        "PoliticalParty":           "flag.fill",

        // ═══════════════════════════════════════════════════
        // Person
        // ═══════════════════════════════════════════════════
        "Person":                   "person.fill",
        "Artist":                   "paintpalette.fill",
        "Painter":                  "paintbrush.fill",
        "CorporateExecutive":       "person.badge.key.fill",
        "Designer":                 "pencil.and.ruler",
        "Executive":                "person.badge.key.fill",
        "Founder":                  "person.badge.plus",
        "GovernmentOfficial":       "person.text.rectangle",
        "Politician":               "person.2",
        "Ruler":                    "crown.fill",
        "SoftwareDeveloper":        "chevron.left.forwardslash.chevron.right",
        "Warlord":                  "shield.lefthalf.filled",

        // ═══════════════════════════════════════════════════
        // Place
        // ═══════════════════════════════════════════════════
        "Place":                    "mappin.and.ellipse",
        "City":                     "building.2.fill",
        "Country":                  "flag.fill",
        "CulturalHeritageSite":     "building.columns",
        "WorldHeritageSite":        "globe",
        "Region":                   "map.fill",

        // ═══════════════════════════════════════════════════
        // PoliticalOrganization
        // ═══════════════════════════════════════════════════
        "PoliticalOrganization":    "flag.fill",
        "PoliticalRegime":          "crown.fill",

        // ═══════════════════════════════════════════════════
        // Product
        // ═══════════════════════════════════════════════════
        "Product":                  "shippingbox.fill",
        "Device":                   "desktopcomputer",
        "AIRobot":                  "figure.stand",
        "DataCollectionDevice":     "antenna.radiowaves.left.and.right",
        "IntegratedCircuit":        "cpu",
        "ASIC":                     "cpu",
        "ManufacturingEquipment":   "hammer.fill",
        "ManufacturingSystem":      "gearshape.2.fill",
        "NotebookComputer":         "laptopcomputer",
        "PersonalComputer":         "desktopcomputer",
        "Robot":                    "figure.stand",
        "HomeRobot":                "house.fill",
        "RobotProduct":             "figure.stand",
        "AutonomousMachine":        "figure.stand",
        "ConsumerRobot":            "figure.stand",
        "HumanoidRobot":            "figure.stand",
        "IndustrialRobot":          "figure.stand",
        "FinancialProduct":         "dollarsign.circle.fill",
        "Currency":                 "dollarsign.circle.fill",
        "InvestmentFund":           "dollarsign.circle.fill",
        "Material":                 "cube.fill",
        "SeafoodBrand":             "fish.fill",
        "MobileGame":               "gamecontroller.fill",
        "PDK":                      "doc.fill",
        "Pharmaceutical":           "cross.case.fill",
        "SoftwareProduct":          "app.fill",
        "AIProduct":                "cpu",
        "AISolution":               "cpu",
        "BusinessPlatform":         "square.grid.3x3.fill",
        "EDAToolSet":               "cpu",
        "CircuitSimulator":         "waveform.path.ecg",
        "LayoutEditor":             "rectangle.split.3x3",
        "VerificationTool":         "checkmark.shield.fill",
        "Game":                     "gamecontroller.fill",
        "MobileApp":                "apps.iphone",
        "SaaSProduct":              "cloud.fill",
        "SoftwareApplication":      "app.fill",
        "SNS":                      "bubble.left.and.bubble.right.fill",
        "SoftwareTool":             "wrench.fill",
        "Vehicle":                  "car.fill",
        "ElectricVehicle":          "bolt.car.fill",

        // ═══════════════════════════════════════════════════
        // Regulation
        // ═══════════════════════════════════════════════════
        "Regulation":               "doc.text.fill",
        "Legislation":              "text.book.closed.fill",
        "Decree":                   "text.book.closed.fill",
        "Policy":                   "doc.text",
        "CompensationSystem":       "dollarsign.circle.fill",
        "CoreValue":                "heart.fill",
        "CorporateMission":         "target",
        "CorporateValue":           "heart.fill",
        "CorporateVision":          "eye.fill",
        "EducationPolicy":          "graduationcap.fill",
        "LandReform":               "map.fill",
        "MonetaryPolicy":           "dollarsign.circle.fill",
        "ReligiousPolicy":          "building.fill",
        "SocialStratification":     "person.3.fill",
        "TradePolicy":              "shippingbox.fill",
        "WeaponConfiscation":       "shield.fill",
        "Standard":                 "checkmark.rectangle",
        "DesignRule":               "checkmark.rectangle",
        "Treaty":                   "pencil",

        // ═══════════════════════════════════════════════════
        // Service
        // ═══════════════════════════════════════════════════
        "Service":                  "wrench.and.screwdriver.fill",
        "DigitalService":           "cloud.fill",
        "AIProgram":                "cpu",
        "CloudService":             "cloud.fill",
        "CodeRepository":           "chevron.left.forwardslash.chevron.right",
        "JobPortal":                "person.crop.circle.badge.checkmark",
        "MediaService":             "play.rectangle.fill",
        "Platform":                 "square.grid.3x3.fill",
        "SocialMediaService":       "bubble.left.and.bubble.right.fill",
        "FinancialService":         "dollarsign.circle.fill",
        "DigitalSecurityService":   "lock.fill",
        "ProfessionalService":      "person.crop.circle.fill",
        "DispatchService":          "person.2.fill",
        "JobPlacementService":      "person.crop.circle.badge.checkmark",
        "PublicService":            "building.2",

        // ═══════════════════════════════════════════════════
        // Technology
        // ═══════════════════════════════════════════════════
        "Technology":               "cpu",
        "Hardware":                 "memorychip",
        "ElectronicComponent":      "cpu",
        "HardwareModule":           "cpu",
        "ProcessDesignKit":         "doc.fill",
        "ProcessNode":              "cpu",
        "ProcessTechnology":        "cpu",
        "QuantumComputer":          "atom",
        "RoboticsModel":            "figure.stand",
        "Semiconductor":            "cpu",
        "SemiconductorManufacturingTechnology": "cpu",
        "LithographyTechnology":    "cpu",
        "TransistorTechnology":     "cpu",
        "SemiconductorTechnology":  "cpu",
        "Software":                 "chevron.left.forwardslash.chevron.right",
        "AIAgent":                  "cpu",
        "AIModel":                  "cpu",
        "VLAModel":                 "cpu",
        "AITechnology":             "cpu",
        "CloudPlatform":            "cloud.fill",
        "DataAnalyticsPlatform":    "chart.bar.fill",
        "DevelopmentTool":          "wrench.fill",
        "EDAツール":                 "cpu",
        "HardwareDescriptionLanguage": "chevron.left.forwardslash.chevron.right",
        "PhysicalAI":               "cpu",
        "SoftwareSystem":           "desktopcomputer",
        "TerminalEmulator":         "terminal.fill",
        "TrustManagementSystem":    "lock.shield.fill",
        "WorldModel":               "globe",

        // ═══════════════════════════════════════════════════
        // Orphan Classes
        // ═══════════════════════════════════════════════════
        "FinancialReport":          "doc.plaintext",
        "FiscalPeriod":             "calendar",
        "Location":                 "mappin.and.ellipse",
    ]

    // MARK: - ルートクラス → 色マッピング（22色）
    // サブクラスの色は BFS で最も近い祖先ルートクラスの色を継承する。

    private static let rootClassColors: [String: Color] = [
        "Person":               Color(.sRGB, red: 0.30, green: 0.69, blue: 0.31, opacity: 1),  // グリーン
        "Organization":         Color(.sRGB, red: 0.25, green: 0.47, blue: 0.85, opacity: 1),  // ブルー
        "Place":                Color(.sRGB, red: 0.90, green: 0.49, blue: 0.13, opacity: 1),  // オレンジ
        "Event":                Color(.sRGB, red: 0.85, green: 0.26, blue: 0.33, opacity: 1),  // レッド
        "Product":              Color(.sRGB, red: 0.61, green: 0.35, blue: 0.71, opacity: 1),  // パープル
        "Activity":             Color(.sRGB, red: 0.96, green: 0.60, blue: 0.10, opacity: 1),  // アンバー
        "Award":                Color(.sRGB, red: 0.80, green: 0.65, blue: 0.05, opacity: 1),  // ゴールド
        "CreativeWork":         Color(.sRGB, red: 0.91, green: 0.44, blue: 0.67, opacity: 1),  // ピンク
        "Education":            Color(.sRGB, red: 0.35, green: 0.34, blue: 0.84, opacity: 1),  // インディゴ
        "Facility":             Color(.sRGB, red: 0.40, green: 0.58, blue: 0.42, opacity: 1),  // セージグリーン
        "GeographicFeature":    Color(.sRGB, red: 0.55, green: 0.60, blue: 0.30, opacity: 1),  // オリーブ
        "Industry":             Color(.sRGB, red: 0.47, green: 0.33, blue: 0.28, opacity: 1),  // ブラウン
        "Market":               Color(.sRGB, red: 0.00, green: 0.59, blue: 0.53, opacity: 1),  // ティール
        "Method":               Color(.sRGB, red: 0.45, green: 0.50, blue: 0.65, opacity: 1),  // スレート
        "Metric":               Color(.sRGB, red: 0.68, green: 0.45, blue: 0.55, opacity: 1),  // モーヴ
        "MilitaryOrganization": Color(.sRGB, red: 0.65, green: 0.20, blue: 0.25, opacity: 1),  // マルーン
        "PoliticalOrganization":Color(.sRGB, red: 0.58, green: 0.25, blue: 0.55, opacity: 1),  // プラム
        "Occupation":           Color(.sRGB, red: 0.58, green: 0.52, blue: 0.46, opacity: 1),  // ウォームグレー
        "Organism":             Color(.sRGB, red: 0.50, green: 0.75, blue: 0.25, opacity: 1),  // ライム
        "Regulation":           Color(.sRGB, red: 0.20, green: 0.52, blue: 0.58, opacity: 1),  // ダークシアン
        "Service":              Color(.sRGB, red: 0.00, green: 0.74, blue: 0.83, opacity: 1),  // シアン
        "Technology":           Color(.sRGB, red: 0.13, green: 0.59, blue: 0.95, opacity: 1),  // ライトブルー
    ]
}
