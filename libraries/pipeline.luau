--!strict

-- localization
local game, table, debug = game, table, debug;
local tableInsert, tableRemove, tableClear = table.insert, table.remove, table.clear;
local profileBegin, profileEnd = debug.profilebegin, debug.profileend;
local drawingNew = Drawing.new;

-- services
local runService = game:GetService("RunService");

-- cache
local maxFrameTime = 0.001; -- 1 millisecond

-- library
local Pipeline = {
    _drawings = {},
    _connections = {},
    _constructs = {},
    _constructLookup = {},
    _constructIndex = 1
}; do
    Pipeline.__index = Pipeline;

    function Pipeline:_addConnection(event: RBXScriptSignal, callback: (...any) -> ()): RBXScriptConnection
        local connection = event:Connect(callback);
        table.insert(self._connections, connection);
        return connection;
    end

    function Pipeline:_updateConstruct(construct: any)
        if construct:IsDestroyed() then return end

        if not construct:IsBuilt() or construct:CanRebuild() then
            if construct:CanRebuild() then
                construct:Clear();
            end

            construct:Build();
        end

        profileBegin("##" .. construct:GetId());
        construct:Update();
        profileEnd();
    end

    function Pipeline:_updateConstructs()
        local startClock = os.clock();
        local totalConstructs = #self._constructs;

        if totalConstructs <= 0 then return end

        profileBegin("Pipeline->Update");

        while (os.clock() - startClock) <= maxFrameTime do
            local index: number = self._constructIndex;
            local construct = self._constructs[index];

            if construct then
                self:_updateConstruct(construct);
            end

            self._constructIndex = (index % totalConstructs) + 1;

            if self._constructIndex == 1 then break end
        end

        profileEnd();
    end

    function Pipeline:_renderConstructs()
        profileBegin("Pipeline->Render");

        for _, construct in self._constructs do
            if construct:IsDestroyed() then continue end
            if not construct:IsBuilt() then continue end

            profileBegin("##" .. construct:GetId());
            construct:Render();
            profileEnd();
        end

        profileEnd();
    end

    function Pipeline:Add(construct: any)
        local id = construct:GetId();

        if self:Get(id) then
            return
        end

        local index = #self._constructs+1;

        self._constructLookup[id] = index;
        tableInsert(self._constructs, index, construct);
    end

    function Pipeline:Get(id: string): any | nil
        local index = self._constructLookup[id];
        return index ~= nil and self._constructs[index] or nil;
    end

    function Pipeline:Remove(id: string, destroy: boolean)
        local construct = self:Get(id);

        if construct and not construct:IsDestroyed() and destroy then
            construct:Destroy();
        end

        local index = self._constructLookup[id];

        if index then
            tableRemove(self._constructs, index);
        end

        self._constructLookup[id] = nil;
    end

    function Pipeline:Create(class: string, properties: {} | nil): any
        local drawing = drawingNew(class);

        if properties then
            for property, value in properties do
                drawing[property] = value;
            end
        end

        return drawing;
    end

    function Pipeline:Load()
        self:_addConnection(runService.PostSimulation, function()
            self:_updateConstructs();
        end);

        self:_addConnection(runService.PreRender, function()
            self:_renderConstructs();
        end);
    end

    function Pipeline:Unload()
        for _, connection in self._connections do
            connection:Disconnect();
        end

        tableClear(self._connections);

        for _, construct in self._constructs do
            self:Remove(construct:GetId(), true);
        end

        tableClear(self._constructs);
        tableClear(self._constructLookup);

        self._constructIndex = nil;

        tableClear(self);
    end
end

local Construct = {}; do
    Construct.__index = Construct;
    Construct.ClassName = "Construct";

    function Construct.new(id: string)
        return setmetatable({
            _id = id,
            _built = false,
            _rebuild = false,
            _destroyed = false,
            _drawings = {}
        }, Construct);
    end

    function Construct:Create(class: string, properties: {} | nil): any
        local drawing = Pipeline:Create(class, properties);
        tableInsert(self._drawings, drawing);
        return drawing;
    end

    function Construct:GetId()
        return self._id;
    end

    function Construct:IsBuilt()
        return self._built;
    end

    function Construct:CanRebuild()
        return self._rebuild;
    end

    function Construct:IsDestroyed()
        return self._destroyed;
    end

    function Construct:Rebuild()
        self._rebuild = true;
    end

    function Construct:Clear()
        for _, drawing in self._drawings do
            drawing:Destroy();
        end

        self._built = false;
        tableClear(self._drawings);
    end

    function Construct:Destroy()
        self:Clear();
        self._destroyed = true;
    end

    function Construct:Build()
        self:OnBuild();
        self._built = true;
        self._rebuild = false;
    end

    function Construct:Update()
        self:OnUpdate();
    end

    function Construct:Render()
        self:OnRender();
    end

    function Construct:OnBuild() end
    function Construct:OnUpdate() end
    function Construct:OnRender() end
end

return Pipeline, Construct;
