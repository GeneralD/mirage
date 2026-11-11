import Dependencies
import Domain
import HostEnvironment
import LogStoreGateway
import OnboardingInteractor
import SupportLogDataSource
import SupportLogRepository
import SupportLogUseCase
import Testing

/// The host registers the live values of the onboarding window's chain and the support log under it
/// (#231): the onboarding interactor, the support log use case, repository and data source, the log
/// store gateway and the host environment. Each is resolved inside `withDependencies { $0.context = .live }`
/// with no override, so the test checks the registration itself, not a fake.
///
/// The onboarding interactor is stateful: it starts a supervisor task when it is made. Resolving it does
/// not start an observation (`start()` does), so the registration is checked here without one.
@Suite("Host registrations of the onboarding and support log", .timeLimit(.minutes(1)))
struct HostOnboardingRegistrationsTests {
    @Test("the live onboarding interactor is OnboardingInteractorImpl")
    func onboardingInteractorIsLive() {
        withDependencies {
            $0.context = .live
        } operation: {
            @Dependency(\.onboardingInteractor) var onboardingInteractor

            #expect(onboardingInteractor is OnboardingInteractorImpl)
        }
    }

    @Test("the live support log use case is SupportLogUseCaseImpl")
    func supportLogUseCaseIsLive() {
        withDependencies {
            $0.context = .live
        } operation: {
            @Dependency(\.supportLogUseCase) var supportLogUseCase

            #expect(supportLogUseCase is SupportLogUseCaseImpl)
        }
    }

    @Test("the live support log repository is SupportLogRepositoryImpl")
    func supportLogRepositoryIsLive() {
        withDependencies {
            $0.context = .live
        } operation: {
            @Dependency(\.supportLogRepository) var supportLogRepository

            #expect(supportLogRepository is SupportLogRepositoryImpl)
        }
    }

    @Test("the live support logs data source is SupportLogDataSourceImpl")
    func supportLogsIsLive() {
        withDependencies {
            $0.context = .live
        } operation: {
            @Dependency(\.supportLogs) var supportLogs

            #expect(supportLogs is SupportLogDataSourceImpl)
        }
    }

    @Test("the live log store gateway is LogStoreGatewayImpl")
    func logStoreGatewayIsLive() {
        withDependencies {
            $0.context = .live
        } operation: {
            @Dependency(\.logStoreGateway) var logStoreGateway

            #expect(logStoreGateway is LogStoreGatewayImpl)
        }
    }

    @Test("the live host environment is HostEnvironmentProviderImpl")
    func hostEnvironmentIsLive() {
        withDependencies {
            $0.context = .live
        } operation: {
            @Dependency(\.hostEnvironment) var hostEnvironment

            #expect(hostEnvironment is HostEnvironmentProviderImpl)
        }
    }

    @Test("the onboarding chain resolves in one live context: the interactor and the five ports under it")
    func onboardingChainResolvesLive() {
        withDependencies {
            $0.context = .live
        } operation: {
            @Dependency(\.onboardingInteractor) var onboardingInteractor
            @Dependency(\.supportLogUseCase) var supportLogUseCase
            @Dependency(\.supportLogRepository) var supportLogRepository
            @Dependency(\.supportLogs) var supportLogs
            @Dependency(\.logStoreGateway) var logStoreGateway
            @Dependency(\.hostEnvironment) var hostEnvironment

            #expect(onboardingInteractor is OnboardingInteractorImpl)
            #expect(supportLogUseCase is SupportLogUseCaseImpl)
            #expect(supportLogRepository is SupportLogRepositoryImpl)
            #expect(supportLogs is SupportLogDataSourceImpl)
            #expect(logStoreGateway is LogStoreGatewayImpl)
            #expect(hostEnvironment is HostEnvironmentProviderImpl)
        }
    }
}
