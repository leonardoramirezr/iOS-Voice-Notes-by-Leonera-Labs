import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var app
    @State private var model: LoginModel
    @FocusState private var focusedField: Field?
    private let expiredEmail: String?

    private enum Field {
        case email
        case code
    }

    init(expiredEmail: String? = nil) {
        self.expiredEmail = expiredEmail
        _model = State(initialValue: LoginModel(email: expiredEmail ?? ""))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                if expiredEmail != nil {
                    Text(L10n.sessionExpired)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.orange)
                }
                switch model.step {
                case .email:
                    emailStep
                case .code:
                    codeStep
                }
                if let error = model.errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                }
                if let signup = URL(string: "https://app.simplenote.com/signup") {
                    Link(L10n.createAccount, destination: signup)
                        .font(.footnote)
                }
            }
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            focusedField = .email
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image("Logo")
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                .accessibilityHidden(true)
            Text(L10n.appName)
                .font(.largeTitle.bold())
            Text(L10n.loginSubtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
    }

    private var emailStep: some View {
        VStack(spacing: 16) {
            TextField(L10n.loginEmail, text: $model.email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .focused($focusedField, equals: .email)
                .onSubmit(sendCode)
                .padding(14)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button(action: sendCode) {
                progressLabel(L10n.loginSendCode)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!model.canSendCode)
        }
    }

    private var codeStep: some View {
        VStack(spacing: 16) {
            Text(L10n.loginCodeSent(model.email))
                .font(.callout)
                .multilineTextAlignment(.center)
            TextField(L10n.loginCode, text: $model.code)
                .textContentType(.oneTimeCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .font(.title2.monospaced())
                .submitLabel(.go)
                .focused($focusedField, equals: .code)
                .onSubmit(logIn)
                .padding(14)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button(action: logIn) {
                progressLabel(L10n.loginLogIn)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!model.canLogIn)
            HStack(spacing: 20) {
                Button(L10n.loginResendCode, action: sendCode)
                Button(L10n.loginDifferentEmail) {
                    model.useDifferentEmail()
                    focusedField = .email
                }
            }
            .font(.footnote)
            .disabled(model.isWorking)
        }
        .onAppear {
            focusedField = .code
        }
    }

    private func progressLabel(_ title: String) -> some View {
        HStack(spacing: 8) {
            if model.isWorking {
                ProgressView()
            }
            Text(title)
        }
        .frame(maxWidth: .infinity)
    }

    private func sendCode() {
        Task {
            await model.sendCode()
        }
    }

    private func logIn() {
        Task {
            if let login = await model.logIn() {
                await app.didLogIn(login)
            }
        }
    }
}
