#!/usr/bin/ruby
# Este programa faz parte da aula de Sistemas Distribuídos da FIAP,
# e tem como intuito ser um cliente de um servidor de chat simples.
#
# O programa abre um socket de escuta em todas as interfaces, na
# porta 7000.
#
# Author:: Hugo Cisneiros (Eitch) (mailto:hugo.cisneiros@gmail.com)
# License:: Do What The Fuck You Want To Public License
require 'socket'

# Responsável por armazenar os usuários que estão
# conectados (depois do handshake) no servidor de chat. Na classe
# pode-se encontrar o nick, nome, sala em que se encontra e um
# descritor com o socket para o envio de mensagens.
class Usuario
    attr_reader :id, :sala, :descriptor
    attr_accessor :nick, :nome

    # Inicializa o usuário já definindo todos as suas informações.
    def initialize(id, nick, nome, descriptor)
        @id = id
        @nick = nick
        @nome = nome
        @descriptor = descriptor
    end

    # Entra em uma sala, avisando ao cliente que foi feito.
    def EntrarSala(nome)
        @sala = nome
        return "RCV_JOINCHN OK #{nome}"
    end

end

# Responsável por armazenar todas as salas disponíveis no servidor.
# Pode-se encontrar as informações de nome, descrição e quais os membros
# (referenciando usuários da classe Usuario).
class Sala
    attr_reader :nome, :descricao, :membros
    attr_accessor :nicks

    # Inicializa a sala, criando-a com suas informações.
    def initialize(nome, descricao)
        @nome = nome
        @descricao = descricao
        @membros = Array.new()
        @nicks = Array.new()
        @log = Array.new()
    end

    # Adiciona um membro na sala.
    def AdicionarMembro(cliente, usuario)
        @membros.push(cliente)
        @nicks.push(usuario)
    end

    # Remove um membro da sala.
    def RemoverMembro(membro, nick)
        @membros.delete(membro)
        @nicks.delete(nick)
    end

    # Adiciona uma linha no registro de conversa da sala.
    def AdicionarLog(linha)
        @log << linha
    end

    # Retorna as mensagens do registro de conversa da sala.
    def VerLog(tail)
        tamanho = @log.length
        inicio = tamanho - tail

        if inicio < 0
            inicio = 0
        end

        return @log[inicio..tamanho]
    end
end

# Contém o servidor de chat em si e a lógica que controla o envio e
# recebimento do protocolo de chat.
class ChatRadicalServer

    attr_reader :salas, :connid, :nicks

    # Inicializa os registros de conexões, nicks e salas.
    def initialize(porta)
        @descriptors = Array.new()
        @connid = 0
        
        @nicks = Hash.new()
        @salas = Hash.new()
        CriaServidor(porta)
    end

    # Cria o servidor na porta determinada. Cria algumas salas padrões
    # e define e gerencia threads para cada conexão recebida.
    def CriaServidor(porta)
        begin
            puts "server> Iniciando servidor na porta #{porta}..."
            server = TCPServer.open(porta)
            server.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
            puts "server> Porta aberta."
        rescue
            puts "error> Erro ao tentar abrir a porta!"
        end

        begin
            puts "server> Criando salas padrões..."
            ["default", "Linux", "Ruby", "FIAP"].each do |nome|
                NovaSala(nome, nome)
            end
            puts "server> Salas criadas."
        rescue
            puts "error> Erro ao crias as salas padrões"
        end

        begin
            loop do
                Thread.start(server.accept) do |cliente|
                    @connid += 1
                    connid = @connid
                    port = cliente.peeraddr[1]
                    host = cliente.peeraddr[2]
                    addr = cliente.peeraddr[3]

                    puts "server> Conexão recebida de #{addr}:#{port}"

                    begin
                        loop do
                            linha = cliente.readline.chomp
                            ClienteConectar(connid,cliente,linha)
                        end
                    rescue
                        puts "server> Desconectado: #{addr}:#{port}"
                    ensure
                        ClienteDesconectar(connid, cliente)
                    end

                end
            end
        rescue Interrupt
           puts "server> Administrador abortou o servidor. Saindo!"
        end 
    end

    # Procedimento de handshake entre o servidor e o cliente.
    def ClienteConectar(connid, cliente, linha)
        # Caso esteja fazendo o handshake
        match = /^CONN ([a-zA-Z0-9]{1,24}) ([a-zA-Z_-]{1,32})$/i.match linha
        if match
            nick = match[1]
            nome = match[2]

            if pegar_usuario_por_nick(nick)
                # Ja existe um apelido conectado
                cliente.puts "RCV_CONN ERR Nick já em uso! Tente outro"
                return 1
            else
                # Completa o handshake
                usuario = Usuario.new(connid, nick, nome, cliente)

		# Adiciona a conexão nos registradores
                @nicks[connid] = usuario
                @descriptors.push(cliente)

		# Manda um OK e a mensagem de boas vindas
                cliente.puts "RCV_CONN OK #{connid}"
                cliente.puts ClienteMotd()
                cliente.puts "RCV_MOTD OK"

		# Coloca o usuário na sala padrão
                @salas["default"].AdicionarMembro(cliente, usuario)
                cliente.puts usuario.EntrarSala('default')
                msg = "#{usuario.nick} entrou na sala 'default'"
                ChatNotice(usuario, msg)

                # O usuário está conectado e aceitando comandos
                loop do
                    ClienteComandos(usuario,cliente)
                end

                return 0
            end
        end

        # Caso queira desconectar
        match = /^QUIT( |$)/i.match linha
        if match
            ClienteDesconectar(connid, cliente)
            return 0
        end

        # Todo o mais, nesta etapa, dá sintaxe incorreta
        cliente.puts "RCV_CONN ERR Sintaxe incorreta"
        return 1
    end

    # Desconecta o cliente do servidor.
    def ClienteDesconectar(connid, cliente)
        # Retira a conexão dos registradores
        @salas.each_value do |sala|
            sala.RemoverMembro(cliente, @nicks[connid])
        end
        @descriptors.delete(cliente)
        @nicks.delete(connid)

        # Fecha o socket
        cliente.close
    end

    # Lê o arquivo de boas vindas (MOTD) para mostrar ao cliente.
    def ClienteMotd()
        motd = String.new()
        begin
            File.open('motd.txt', 'r') do |arquivo|
                while linha = arquivo.gets
                    motd = motd + linha
                end
            end
            return motd
        rescue
            puts "error> Erro ao ler o arquivo MOTD! Mostrando mensagem meia-boca."
            return "Bem vindo ao ChatRadical!"
        end
    end

    # Escuta os comandos enviados pelos clientes e de acordo com o protocolo
    # de chat, chama outros métodos para definir o que fazer.
    def ClienteComandos(usuario, cliente)
        # Le a linha enviada pelo cliente
        linha = cliente.readline.chomp

        match = /^CMD_LISTCHN( |$)/i.match linha
        if match
            cliente.puts CliListarSalas()
            return 0
        end

        match = /^CMD_JOINCHN ([a-zA-Z0-9]{1,24})( (.+))?/i.match linha
        if match
            CliEntrarSala(cliente, usuario, match[1], match[3])
            return 0
        end

        match = /^CMD_INFOCHN( |$)/i.match linha
        if match
            cliente.puts CliInfoSala(usuario.sala)
            return 0
        end

        match = /^CMD_WHOCHN( |$)/i.match linha
        if match
            cliente.puts CliUsuariosSala(usuario.sala)
            return 0
        end

        match = /^CMD_VLOG( ([0-9]{1,2}))?/.match linha
        if match
            CliVerLog(cliente, usuario.sala, match[2])
            return 0
        end

        match = /^CMD_PVT ([a-zA-Z0-9]{1,24}) (.+)/i.match linha
        if match
            cliente.puts EnviarPVT(usuario, match[1], match[2])
            return 0
        end

        match = /^CMD_NICK ([a-zA-Z0-9]{1,24})/i.match linha
        if match
            cliente.puts CliNick(usuario, match[1])
            return 0
        end

        match = /^CMD_CHAT (.+)/i.match linha
        if match
            cliente.puts Chat(match[1], usuario)
            return 0
        end

        match = /^QUIT( |$)/i
        if match
            msg = "#{usuario.nick} saiu da sala"
            ChatNotice(usuario, msg)
            ClienteDesconectar(usuario.id, cliente)
            return 0
        end

        # Qualquer outro comando é inválido
        cliente.puts "ERR_CMD Comando Invalido"
        return 1
    end

    # Obtém uma classe usuário através do seu nick
    def pegar_usuario_por_nick(nick)
        @nicks.each_value do |usuario|
            if usuario.nick == nick
                return usuario
            end
        end

        return false
    end

    # Obtém a descrição de uma sala através do seu nome
    def pegar_descricao_de_sala_por_nome(nome)
        @salas.each_value do |sala|
            if (sala.nome == nome)
                return sala.descricao
            end
        end

        return false
    end

    # Cria uma nova sala
    def NovaSala(nome, descricao=nil)
        unless @salas[nome]
            if descricao == nil
                return false
            end

            @salas[nome] = Sala.new(nome, descricao)
            puts "server> Nova sala criada: #{nome} - #{descricao}"

            return true
        end
        return true
    end

    # Lista as salas do servidor
    def ListarSalas()
        lista = Array.new()
        @salas.each_value do |sala|
            nome = sala.nome
            descricao = sala.descricao
            
            lista = lista + ["#{nome} - #{descricao}"]
        end
        return lista.sort
    end

    # Gera uma mensagem de chat e manda para os clientes da sala
    def Chat(linha, usuario)
        sala = @salas[usuario.sala]
        msg = Time.now.strftime("[%H:%M:%S] ") + "<#{usuario.nick}> #{linha}"

        sala.AdicionarLog(msg)
        
        membros = sala.membros
        membros.each do |cliente|
            cliente.puts "RCV_CHATMSG #{msg}"
        end

        return "RCV_CHAT OK"
    end

    # Gera uma mensagem de notificação e manda para os clientes da sala
    def ChatNotice(usuario, msg)
        msg = Time.now.strftime("[%H:%M:%S] ") + "*** #{msg}"

        sala = @salas[usuario.sala]
        sala.AdicionarLog(msg)

        membros = sala.membros
        membros.each do |cliente|
            cliente.puts "RCV_CHATMSG #{msg}"
        end

        return "RCV_CHAT OK"
    end

    # Envia uma mensagem privada para um usuário
    def EnviarPVT(usuario, destino, msg)
         destino = pegar_usuario_por_nick(destino)

         if destino
             msg = Time.now.strftime("[%H:%M:%S] ") + "PVT <#{usuario.nick}> #{msg}"
             destino.descriptor.puts "RCV_CHATMSG #{msg}"
             return "RCV_PVT OK"
         else
             return "RCV_PVT ERR Nick não existe!"
         end
    end

    # Trata o comando de listar salas enviado pelo usuário
    def CliListarSalas
        lista = ListarSalas()
        retorno = "RCV_LISTCHN OK "
        lista.each do |sala|
            retorno = retorno + sala + "|"
        end
        return retorno
    end

    # Trata o comando de entrar em uma sala enviado pelo usuário
    def CliEntrarSala(cliente, usuario, sala, descricao=nil)
        unless NovaSala(sala, descricao)
            return "RCV_JOINCHN ERR Necessário uma descrição para criar uma sala."
        else
            sala_atual = usuario.sala
            if sala_atual
                msg = "#{usuario.nick} saiu da sala"
                ChatNotice(usuario, msg)
                @salas[sala_atual].RemoverMembro(cliente, usuario)
            end

            @salas[sala].AdicionarMembro(cliente, usuario)
            cliente.puts usuario.EntrarSala(sala)

            msg = "#{usuario.nick} entrou na sala '#{sala}'"
            ChatNotice(usuario, msg)
            return 0
        end
    end

    # Trata o comando de informações da sala atual enviado pelo usuário
    def CliInfoSala(sala)
        return "RCV_INFOCHN OK #{@salas[sala].nome} #{@salas[sala].descricao}"
    end

    # Trata o comando de informações de usuários em uma sala enviado
    # pelo usuário
    def CliUsuariosSala(sala)
        retorno = "RCV_WHOCHN OK "
        @salas[sala].nicks.each do |umusuario|
            retorno = retorno + "#{umusuario.nick}|"
        end
        return retorno
    end

    # Trata o comando de ver o registro de conversa de um canal enviado
    # pelo usuário
    def CliVerLog(cliente, sala, tail)
        if tail == nil
            tail = 30
        else
            tail = tail.to_i
        end

        cliente.puts tail

        log = @salas[sala].VerLog(tail)

        log.each do |linha_log|
            cliente.puts "RCV_CHATLOG [LOG] #{linha_log}"
        end
        return 0
    end

    # Trata o comando de mudança de nick enviado pelo usuário
    def CliNick(usuario, nick)
        if pegar_usuario_por_nick(nick)
            return "RCV_NICK ERR Nick já em uso"
        else
            #@nicks[usuario.id] = novo_nick
            #@salas[usuario.sala].RemoverMembro(cliente, usuario)
            #@salas[usuario.sala].AdicionarMembro(cliente, novo_nick)

            nick_velho = usuario.nick
            usuario.nick = nick

            msg = "#{nick_velho} trocou de nick para '#{nick}'"
            ChatNotice(usuario, msg)

            return "RCV_NICK OK"
        end
    end

end

server = ChatRadicalServer.new(7000)
