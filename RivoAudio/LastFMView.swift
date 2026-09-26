import SwiftUI

struct LastFMView: View {
    @EnvironmentObject var client: LastFMClient
    @EnvironmentObject var history: ListeningHistory
    @Environment(\.openURL) private var openURL
    @State private var key = ""
    @State private var secret = ""
    var body: some View {
        List {
            Section("Last.fm") {
                if client.connected {
                    LabeledContent("Cuenta", value: client.username)
                    Toggle("Enviar escuchas", isOn: $client.enabled)
                        .onChange(of: client.enabled) { _, active in if active { Task { await client.flush() } } }
                    Button("Desconectar", role: .destructive) { client.disconnect() }
                } else {
                    if !client.configured {
                        SecureField("API key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Shared secret", text: $secret).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("Guardar credenciales") {
                            do { try client.configure(key: key, secret: secret); key = ""; secret = "" }
                            catch { client.status = error.localizedDescription }
                        }
                        Link("Obtener una API key de Last.fm", destination: URL(string: "https://www.last.fm/api/account/create")!)
                        Text("La key y el shared secret se guardan en el llavero del iPhone. Tu contraseña se introduce únicamente en Last.fm al autorizar.").font(.footnote)
                    } else {
                        Button("Autorizar en Last.fm") { Task { if let url = await client.beginAuthorization() { openURL(url) } } }
                            .disabled(client.busy)
                        if client.authorizing {
                            Button("Ya autoricé · conectar cuenta") { Task { await client.finishAuthorization() } }.disabled(client.busy)
                        }
                    }
                }
                Text(client.status).font(.footnote).foregroundStyle(.secondary)
            }
            if client.configured {
                Section("Cambiar credenciales API") {
                    SecureField("Nueva API key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Nuevo shared secret", text: $secret).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Guardar y volver a autorizar") {
                        do { try client.configure(key: key, secret: secret); key = ""; secret = "" }
                        catch { client.status = error.localizedDescription }
                    }.disabled(key.isEmpty || secret.isEmpty || client.busy)
                }
            }
            Section("Pendientes de Last.fm") {
                let queue = client.pending.filter { $0.account == client.username }
                Text("\(queue.filter { $0.rejection == nil }.count) por enviar")
                Button("Reintentar ahora") { Task { await client.flush() } }.disabled(!client.connected)
                ForEach(queue.filter { $0.rejection != nil }) { entry in
                    VStack(alignment: .leading) {
                        Text(entry.title)
                        Text(entry.rejection ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if queue.contains(where: { $0.rejection != nil }) {
                    Button("Quitar rechazadas de la cola", role: .destructive) { client.clearRejected() }
                }
            }
            Section("Historial en este iPhone") {
                ForEach(history.entries.prefix(100)) { item in
                    VStack(alignment: .leading) {
                        Text(item.title).font(.headline)
                        Text("\(item.artist) · \(item.startedAt.formatted())").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.navigationTitle("Scrobbling")
    }
}
