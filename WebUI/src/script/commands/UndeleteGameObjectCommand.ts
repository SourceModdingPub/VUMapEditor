import Command from '../libs/three/Command';
import { GameObjectTransferData } from '@/script/types/GameObjectTransferData';
import { VextCommand } from '@/script/types/VextCommand';

export default class UndeleteGameObjectCommand extends Command {
	constructor(private gameObjectTransferData: GameObjectTransferData) {
		super('UndeleteGameObjectCommand');
		this.name = 'Undelete GameObject';
		this.gameObjectTransferData = gameObjectTransferData;
	}

	public execute() {
		const gameObjectTransferData = new GameObjectTransferData({
			guid: this.gameObjectTransferData.guid,
			origin: this.gameObjectTransferData.origin
		});
		window.vext.SendCommand(new VextCommand(this.type, gameObjectTransferData)); // the lua side doesnt need the gameObjectTransferData just to delete the object, so we save memory
	}

	public undo() {
		window.vext.SendCommand(new VextCommand('DeleteGameObjectCommand', this.gameObjectTransferData));
	}
}
